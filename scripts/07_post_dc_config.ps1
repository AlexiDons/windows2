$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --== CONFIGURATIE VARIABELEN ==--
$caCommonName = 'WS2-CA'
$gpoName      = 'Domain-Wide Certificate Auto-Enrollment'

Write-Host "STEP 1: Waiting for Active Directory to become available" -ForegroundColor Yellow
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
        Write-Host "Attempt $attempt/$maxAttempts AD is not yet ready. Waiting 10 seconds"
        Start-Sleep -Seconds 10
    }
}

if (-not $domain) {
    Write-Error "Failed to connect to Active Directory after $maxAttempts attempts. Exiting."
    exit 1
}

Write-Host "STEP 2: Installing AD Certificate Services and Web Enrollment" -ForegroundColor Yellow

# Install the main AD CS Role if the service is not present
if (-not (Get-Service 'CertSvc' -ErrorAction SilentlyContinue)) {
    Write-Host "Installing ADCS-Certification-Authority feature"
    Install-WindowsFeature -Name 'ADCS-Cert-Authority'
    
    Write-Host "Configuring the service as an Enterprise Root CA"
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
    Write-Host "Installing ADCS-Web-Enrollment feature"
    Install-WindowsFeature -Name 'ADCS-Web-Enrollment'
} else {
    Write-Host "AD CS Web Enrollment feature is already installed." -ForegroundColor Cyan
}
Start-Sleep -Seconds 15


Write-Host "STEP 2b: Ensuring IIS + Web Enrollment are configured" -ForegroundColor Yellow

# IIS prerequisites (idempotent)
$webFeatures = @(
  'Web-Server','Web-Common-Http','Web-Default-Doc','Web-Static-Content',
  'Web-Http-Errors','Web-Http-Logging','Web-Request-Monitor','Web-Filtering',
  'Web-Windows-Auth'
)
$missing = (Get-WindowsFeature $webFeatures | Where-Object InstallState -ne 'Installed').Name
if ($missing) {
    Write-Host "Installing IIS features: $($missing -join ', ')"
    Install-WindowsFeature -Name $missing -IncludeManagementTools | Out-Null
} else {
    Write-Host "IIS features already installed." -ForegroundColor Cyan
}

# Make sure CA service exists and is running
$certSvc = Get-Service -Name 'CertSvc' -ErrorAction SilentlyContinue
if ($certSvc -and $certSvc.Status -ne 'Running') {
    Start-Service 'CertSvc'
}

# Configure Web Enrollment (create /CertSrv if missing)
Import-Module WebAdministration
$certSrvExists = $false
try {
    $apps = Get-WebApplication -Site 'Default Web Site' -ErrorAction SilentlyContinue
    $certSrvExists = $apps | Where-Object { $_.path -eq '/CertSrv' } | ForEach-Object { $true } | Select-Object -First 1
} catch { $certSrvExists = $false }

if (-not $certSrvExists) {
    Write-Host "Running Install-AdcsWebEnrollment to create /CertSrv"
    Install-AdcsWebEnrollment -Force | Out-Null
} else {
    Write-Host "/CertSrv already present." -ForegroundColor Cyan
}

# Ensure Default Web Site exists and is started
if (-not (Get-Website -Name 'Default Web Site' -ErrorAction SilentlyContinue)) {
    New-Website -Name 'Default Web Site' -Port 80 -PhysicalPath 'C:\inetpub\wwwroot' | Out-Null
}
Start-Website -Name 'Default Web Site' | Out-Null

# Configure authentication and providers for /CertSrv
try {
    $loc = 'Default Web Site/CertSrv'
    $provPath = "system.webServer/security/authentication/windowsAuthentication/providers"

    Set-WebConfigurationProperty -PSPath 'IIS:\' -Location $loc `
        -Filter "system.webServer/security/authentication/windowsAuthentication" `
        -Name enabled -Value $true

    Set-WebConfigurationProperty -PSPath 'IIS:\' -Location $loc `
        -Filter "system.webServer/security/authentication/anonymousAuthentication" `
        -Name enabled -Value $true

    Set-WebConfigurationProperty -PSPath 'IIS:\' -Location $loc `
        -Filter "system.webServer/security/access" `
        -Name sslFlags -Value 0

    $existing = @()
    try {
        $existing = (Get-WebConfiguration -PSPath 'IIS:\' -Location $loc -Filter $provPath).Collection.value
    } catch { $existing = @() }

    function Add-ProviderIfMissing {
        param([string]$name)
        if (-not ($existing -contains $name)) {
            Add-WebConfiguration -PSPath 'IIS:\' -Location $loc -Filter $provPath -Value @{ value = $name } | Out-Null
            $script:existing += $name
        }
    }
    Add-ProviderIfMissing 'Negotiate'
    Add-ProviderIfMissing 'NTLM'

    foreach ($p in @('Negotiate','NTLM')) {
        Remove-WebConfigurationProperty -PSPath 'IIS:\' -Location $loc -Filter $provPath -Name "." -AtElement @{value=$p} -ErrorAction SilentlyContinue
    }
    Add-WebConfiguration -PSPath 'IIS:\' -Location $loc -Filter $provPath -Value @{ value = 'Negotiate' } | Out-Null
    Add-WebConfiguration -PSPath 'IIS:\' -Location $loc -Filter $provPath -Value @{ value = 'NTLM' }      | Out-Null

    Write-Host "/CertSrv authentication configured (Windows + Anonymous, sslFlags=None)." -ForegroundColor Green
} catch {
    Write-Warning "Could not set authentication/providers on /CertSrv: $($_.Exception.Message)"
}

Write-Host "STEP 3: Publishing CA certificate and CRL to Active Directory" -ForegroundColor Yellow

# Export CA cert
$cerPath = "C:\$($caCommonName -replace '[^A-Za-z0-9\-]','_').cer"
certutil -ca.cert $cerPath | Out-Null

# Publish to AD
certutil -dspublish -f $cerPath RootCA   | Out-Null
certutil -dspublish -f $cerPath NTAuthCA | Out-Null
certutil -dspublish -f $cerPath SubCA    | Out-Null
certutil -crlpublish                      | Out-Null

Write-Host "CA certificate and CRL published to AD." -ForegroundColor Green

Write-Host "STEP 4: Configuring domain-wide certificate auto-enrollment GPO" -ForegroundColor Yellow

# Try to import GroupPolicy module
$gpModuleLoaded = $false
try { Import-Module GroupPolicy -ErrorAction Stop; $gpModuleLoaded = $true } catch { Write-Host "GroupPolicy module not available; skipping GPO step." -ForegroundColor DarkYellow }

if ($gpModuleLoaded) {
    $domainDN = (Get-ADDomain).DistinguishedName
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $gpoName
    }

    # Link idempotent met juiste enumwaarden (Yes/No)
    $inherit = Get-GPInheritance -Target $domainDN
    $link = $inherit.GpoLinks | Where-Object { $_.DisplayName -eq $gpo.DisplayName }

    if ($null -eq $link) {
        New-GPLink -Name $gpo.DisplayName -Target $domainDN -LinkEnabled Yes -Enforced No | Out-Null
        Write-Host "Created and linked GPO '$gpoName' to domain root." -ForegroundColor Green
    } else {
        Set-GPLink -Name $gpo.DisplayName -Target $domainDN -LinkEnabled Yes -Enforced No | Out-Null
        Write-Host "Updated existing link for GPO '$gpoName' at domain root." -ForegroundColor Green
    }

    # AEPolicy = 7 (Enable + Renew + Update)
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "AEPolicy" -Type DWord -Value 7
    Set-GPRegistryValue -Name $gpoName -Key "HKCU\Software\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "AEPolicy" -Type DWord -Value 7
    Write-Host "Auto-enrollment policy configured." -ForegroundColor Green
}

Write-Host "STEP 5: Ensuring firewall allows HTTP (80)" -ForegroundColor Yellow
if (-not (Get-NetFirewallRule -DisplayName 'Allow HTTP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Allow HTTP' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow | Out-Null
    Write-Host "Firewall rule 'Allow HTTP' created." -ForegroundColor Green
} else {
    Write-Host "Firewall rule 'Allow HTTP' already exists." -ForegroundColor Cyan
}

Write-Host "STEP 6: Health check for /CertSrv" -ForegroundColor Yellow
try {
    $fqdn = ('{0}.{1}' -f $env:COMPUTERNAME,(Get-ADDomain).DNSRoot)
    $resp = Invoke-WebRequest -Uri ("http://{0}/CertSrv" -f $fqdn) -Method Head -UseBasicParsing -ErrorAction Stop
    Write-Host "OK: /CertSrv reachable on http://$fqdn/CertSrv (HTTP $($resp.StatusCode))." -ForegroundColor Green
} catch {
    Write-Host "Warning: /CertSrv not reachable yet. Check DNS and client browser 'Local intranet' zone." -ForegroundColor DarkYellow
}
