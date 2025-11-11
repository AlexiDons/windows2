<#
.SYNOPSIS
    Installs and configures Active Directory Certificate Services (AD CS) as an Enterprise Root CA.
    This script is designed to be idempotent and can be re-run safely.

.DESCRIPTION
    1. Waits for Active Directory to be available.
    2. Installs the AD CS role and the Web Enrollment feature.
    3. Configures the Certificate Authority.
    4. Publishes the CA certificate to Active Directory for domain-wide trust.
    5. Creates and configures a Group Policy Object (GPO) for automatic certificate enrollment.
    6. Configures necessary firewall rules for AD CS, DHCP, DNS, and Domain Controller services.
#>

# --- Script Configuration ---
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- Variables ---
$caCommonName = 'WS2-CA'
$gpoName      = 'Domain-Wide Certificate Auto-Enrollment'

#================================================================================
# STEP 1: WAIT FOR ACTIVE DIRECTORY DOMAIN SERVICES
#================================================================================
Write-Host "STEP 1: Waiting for Active Directory to become available..." -ForegroundColor Yellow
$maxAttempts = 20
$attempt = 0
while ($attempt -lt $maxAttempts) {
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Host "Success: Connected to domain '$($domain.DNSRoot)'." -ForegroundColor Green
        break
    }
    catch {
        $attempt++
        Write-Host "Attempt $attempt/$maxAttempts AD is not yet ready. Waiting 10 seconds..."
        Start-Sleep -Seconds 10
    }
}

if (-not $domain) {
    Write-Error "Failed to connect to Active Directory after $maxAttempts attempts. Exiting."
    exit 1
}

#================================================================================
# STEP 2: INSTALL AD CS ROLE AND WEB ENROLLMENT
#================================================================================
Write-Host "STEP 2: Installing AD Certificate Services and Web Enrollment..." -ForegroundColor Yellow

# Install the main AD CS Role if the service is not present
if (-not (Get-Service 'CertSvc' -ErrorAction SilentlyContinue)) {
    Write-Host "Installing ADCS-Certification-Authority feature..."
    Install-WindowsFeature -Name 'ADCS-Cert-Authority'
    
    Write-Host "Configuring the service as an Enterprise Root CA..."
    Install-AdcsCertificationAuthority -CAType EnterpriseRootCA `
        -CACommonName $caCommonName `
        -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' `
        -KeyLength 2048 `
        -HashAlgorithmName 'SHA256' `
        -ValidityPeriod Years `
        -ValidityPeriodUnits 10 `
        -Force
} else {
    Write-Host "AD CS Certification Authority service is already installed." -ForegroundColor Cyan
}

# Install the Web Enrollment feature
if (-not (Get-WindowsFeature 'ADCS-Web-Enrollment').Installed) {
    Write-Host "Installing ADCS-Web-Enrollment feature..."
    Install-WindowsFeature -Name 'ADCS-Web-Enrollment'
} else {
    Write-Host "AD CS Web Enrollment feature is already installed." -ForegroundColor Cyan
}

#================================================================================
# STEP 3: PUBLISH CA CERTIFICATE TO ACTIVE DIRECTORY
#================================================================================
Write-Host "STEP 3: Publishing CA certificate to Active Directory..." -ForegroundColor Yellow

# Wait for the CA service to be running and the certificate to be generated
Start-Sleep -Seconds 15
$rootCert = Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.Subject -like "CN=$caCommonName*" } | Select-Object -First 1

if ($rootCert) {
    $cerPath = "C:\$($caCommonName).cer"
    Export-Certificate -Cert $rootCert -FilePath $cerPath
    
    Write-Host "Publishing certificate to 'RootCA' store in AD..."
    certutil.exe -f -dspublish "$cerPath" RootCA
    
    Write-Host "Publishing certificate to 'NTAuthCA' store in AD..."
    certutil.exe -f -dspublish "$cerPath" NTAuthCA
    
    Write-Host "Success: Certificate published to AD." -ForegroundColor Green
} else {
    Write-Error "Could not find the generated CA certificate. Cannot publish to AD."
}

#================================================================================
# STEP 4: CONFIGURE GROUP POLICY FOR AUTO-ENROLLMENT (fixed)
#================================================================================
Write-Host "STEP 4: Configuring Group Policy for auto-enrollment..." -ForegroundColor Yellow

# Zorg dat de GroupPolicy-cmdlets aanwezig zijn
if (-not (Get-WindowsFeature GPMC).Installed) {
    Install-WindowsFeature -Name GPMC | Out-Null
}
Import-Module GroupPolicy -ErrorAction Stop

$domainDN = (Get-ADDomain).DistinguishedName
$gpoName  = 'Domain-Wide Certificate Auto-Enrollment'

# GPO ophalen of aanmaken
$gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    Write-Host "Creating new GPO: '$gpoName'..."
    $gpo = New-GPO -Name $gpoName -Comment "Provides domain-wide settings for certificate auto-enrollment."
} else {
    Write-Host "GPO '$gpoName' already exists." -ForegroundColor Cyan
}

# Check of de GPO al gelinkt is aan de domeinroot
$inherit = Get-GPInheritance -Target $domainDN    # bevat .GpoLinks
$alreadyLinked = $false
if ($inherit -and $inherit.GpoLinks) {
    $alreadyLinked = $inherit.GpoLinks | Where-Object { $_.DisplayName -eq $gpo.DisplayName } | ForEach-Object { $true } | Select-Object -First 1
}

# Linken indien nog niet gelinkt
if (-not $alreadyLinked) {
    New-GPLink -Name $gpo.DisplayName -Target $domainDN | Out-Null
    Write-Host "GPO linked to domain root '$domainDN'."
} else {
    Write-Host "GPO is already linked to the domain root." -ForegroundColor Cyan
}

# Auto-enrollment aanzetten (AEPolicy=7)
Set-GPRegistryValue -Name $gpo.DisplayName `
  -Key 'HKLM\Software\Policies\Microsoft\Cryptography\AutoEnrollment' `
  -ValueName 'AEPolicy' -Type DWord -Value 7

Write-Host "Success: GPO configured for auto-enrollment." -ForegroundColor Green


#================================================================================
# STEP 5: Enabling necessary firewall rules... (robust version)
#================================================================================
Write-Host "STEP 5: Enabling necessary firewall rules..." -ForegroundColor Yellow

$firewallGroups = @(
    "Active Directory Domain Controller",
    "DNS Server",
    "DHCP Server"
)

foreach ($group in $firewallGroups) {
    Write-Host "Enabling rules for '$group'..."
    Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue | Enable-NetFirewallRule
}

# --- AD CS (RPC/DCOM) ---
# Try a built-in group if it exists; otherwise fall back to explicit rules.
$csGroup = "Active Directory Certificate Services"
$hasGroup = (Get-NetFirewallRule -DisplayGroup $csGroup -ErrorAction SilentlyContinue) | Measure-Object | Select-Object -ExpandProperty Count
if ($hasGroup -gt 0) {
    Enable-NetFirewallRule -DisplayGroup $csGroup | Out-Null
    Write-Host "Enabled firewall group '$csGroup'."
} else {
    Write-Host "No '$csGroup' group found. Applying explicit RPC/DCOM rules for AD CS..."

    # DCOM general allow (if present on this OS)
    $comGroup = "COM+ Network Access"
    $hasCom = (Get-NetFirewallRule -DisplayGroup $comGroup -ErrorAction SilentlyContinue) | Measure-Object | Select-Object -ExpandProperty Count
    if ($hasCom -gt 0) {
        Enable-NetFirewallRule -DisplayGroup $comGroup | Out-Null
        Write-Host "Enabled firewall group '$comGroup'."
    }

    # RPC Endpoint Mapper (TCP 135) — required for DCOM activation
    New-NetFirewallRule -DisplayName "RPC Endpoint Mapper (TCP 135)" `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 135 `
        -Profile Domain -ErrorAction SilentlyContinue | Out-Null

    # RPC dynamic ports (TCP) for DCOM callbacks. Domain profile only.
    # NOTE: this opens the standard dynamic range used by modern Windows.
    New-NetFirewallRule -DisplayName "RPC Dynamic Ports (TCP 49152-65535)" `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 49152-65535 `
        -Profile Domain -ErrorAction SilentlyContinue | Out-Null
}

# Web Enrollment HTTP/HTTPS
New-NetFirewallRule -DisplayName "AD CS Web (HTTP-In)"  -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80  -Profile Domain -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "AD CS Web (HTTPS-In)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443 -Profile Domain -ErrorAction SilentlyContinue | Out-Null

# WinRM for provisioning (helpful with Vagrant/Ansible)
New-NetFirewallRule -DisplayName "WinRM (5985)" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -ErrorAction SilentlyContinue | Out-Null

Write-Host "Success: Firewall rules configured." -ForegroundColor Green
