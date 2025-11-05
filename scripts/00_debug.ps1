# 00_dns_ad_diagnose.ps1

# Wacht tot AD volledig operationeel is
$maxAttempts = 30
$attempt = 0
Write-Host "Wachten tot Active Directory volledig operationeel is..."
while ($attempt -lt $maxAttempts) {
    $attempt++
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Host "AD is operationeel: $($domain.DNSRoot)"
        break
    } catch {
        Write-Host "Poging $attempt/$maxAttempts - wacht 10 seconden..."
        Start-Sleep -Seconds 10
    }
}

if ($attempt -eq $maxAttempts) {
    Write-Error "Timeout: AD niet operationeel"
    exit 1
}

# Extra wachttijd om AD volledig te laten stabiliseren na de reboot.
Write-Host "AD is online. Wacht 30 seconden extra voor stabilisatie..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

$ErrorActionPreference = 'Stop'
Write-Host "=== AD/DNS diagnose (server1) ===" -ForegroundColor Cyan

function Test-IsDomainController {
  # DC's hebben de NTDS-service (Directory Services) geïnstalleerd
  $ntds = Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS' -ErrorAction SilentlyContinue
  return ($null -ne $ntds)
}

function Test-Feature($name) {
  $f = Get-WindowsFeature -Name $name -ErrorAction SilentlyContinue
  if ($null -eq $f) { return @{ Name=$name; Installed=$false } }
  return @{ Name=$name; Installed=$f.Installed }
}

$comp = $env:COMPUTERNAME
$diag = [ordered]@{}

# 1) Is DC (zonder AD-cmdlets)
$diag.IsDomainController = Test-IsDomainController

# 2) AD-module aanwezig?
$adMod = Get-Module -ListAvailable ActiveDirectory -ErrorAction SilentlyContinue
$diag.ADModule = ($null -ne $adMod)

# 3) DNS-serverrol/service
$dnsSvc = Get-Service -Name DNS -ErrorAction SilentlyContinue
$diag.DNSServerServicePresent = ($null -ne $dnsSvc)
$diag.DNSServerServiceStatus  = if ($null -ne $dnsSvc) { $dnsSvc.Status } else { "NotInstalled" }

# 4) Windows Features
$diag.Features = @(
  Test-Feature "AD-Domain-Services",
  Test-Feature "DNS",
  Test-Feature "RSAT-AD-PowerShell"
)

# 5) AD-domeinnaam ophalen (alleen als DC + AD-module)
if ($diag.IsDomainController -and $diag.ADModule) {
  try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $dom = Get-ADDomain -ErrorAction Stop
    $diag.DomainDNSName = $dom.DNSRoot
  } catch {
    $diag.DomainDNSName = $null
  }
} else {
  $diag.DomainDNSName = $null
}

# 6) Resolver-adressen
try {
  $nic = Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object { $null -ne $_.ServerAddresses } |
        Select-Object -First 1
  $diag.DNSClientServers = if ($null -ne $nic) { $nic.ServerAddresses } else { @() }
} catch { $diag.DNSClientServers = @() }

# 7) Lokale DNS WMI/CIM call
try {
  $null = Get-DnsServerZone -ComputerName $comp -ErrorAction Stop
  $diag.LocalCIMtoDNS = "OK"
} catch {
  $diag.LocalCIMtoDNS = $_.Exception.Message
}

$diag.GetEnumerator() | ForEach-Object {
  "{0} : {1}" -f $_.Key, (($_.Value | ConvertTo-Json -Compress))
} | Write-Host

Write-Host "`nCONCLUSIE:" -ForegroundColor Yellow
if (-not $diag.IsDomainController) {
  Write-Host "- Deze server is (nog) geen DC. Promoot eerst tot DC, reboot, en voer daarna het AD-only DNS script uit." -ForegroundColor Red
}
if (-not $diag.ADModule) {
  Write-Host "- ActiveDirectory PowerShell module ontbreekt. Installeer RSAT-AD-PowerShell (of management tools) op de DC." -ForegroundColor Red
}
if (-not $diag.DNSServerServicePresent -or $diag.DNSServerServiceStatus -ne "Running") {
  Write-Host "- DNS-serverrol draait niet. Installeer/Start de DNS service." -ForegroundColor Red
}
if ($diag.IsDomainController -and $diag.ADModule -and $null -eq $diag.DomainDNSName) {
  Write-Host "- Get-ADDomain faalt. Controleer AD-replicatie/DNS of herstart na promotie." -ForegroundColor Red
}
