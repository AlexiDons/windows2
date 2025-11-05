
# 05_configure_dhcp.ps1 (fixed)

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

Write-Host "--- Stap 5: DHCP Server configureren... ---" -ForegroundColor Green

$domainName  = "WS2-25-alexi.hogent"
$serverFQDN  = "server1.$domainName"
$serverIP    = "192.168.25.10"

$scopeID     = "192.168.25.0"
$scopeName   = "WS2_Scope"
$startRange  = "192.168.25.50"
$endRange    = "192.168.25.150"
$excludedStart = "192.168.25.101"
$excludedEnd   = "192.168.25.150"
$router      = "192.168.25.1"
$dnsServer   = $serverIP

# Security groups + service
try { netsh dhcp add securitygroups | Out-Null } catch {}
Restart-Service -Name DhcpServer -Force

# Authorize DHCP in AD (Enterprise Admins required)
if (-not (Get-DhcpServerInDC -ErrorAction SilentlyContinue | Where-Object { $_.DnsName -ieq $serverFQDN })) {
    Write-Host "DHCP Server autoriseren in AD..."
    Add-DhcpServerInDC -DnsName $serverFQDN -IpAddress $serverIP
} else {
    Write-Host "DHCP Server is al geautoriseerd in AD."
}

# Scope + opties
if (-not (Get-DhcpServerv4Scope -ComputerName $serverFQDN -ScopeId $scopeID -ErrorAction SilentlyContinue)) {
    Write-Host "DHCP Scope $scopeName wordt aangemaakt..."
    Add-DhcpServerv4Scope -ComputerName $serverFQDN -Name $scopeName -StartRange $startRange -EndRange $endRange -SubnetMask 255.255.255.0
    Add-DhcpServerv4ExclusionRange -ComputerName $serverFQDN -ScopeId $scopeID -StartRange $excludedStart -EndRange $excludedEnd
    Set-DhcpServerv4OptionValue -ComputerName $serverFQDN -ScopeId $scopeID -OptionId 3  -Value $router
    Set-DhcpServerv4OptionValue -ComputerName $serverFQDN -ScopeId $scopeID -OptionId 6  -Value $dnsServer
    Set-DhcpServerv4OptionValue -ComputerName $serverFQDN -ScopeId $scopeID -OptionId 15 -Value $domainName
    Write-Host "DHCP Scope $scopeName is geconfigureerd."
} else {
    Write-Host "DHCP Scope $scopeName is al geconfigureerd."
}