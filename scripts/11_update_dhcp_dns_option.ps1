$ErrorActionPreference = 'Stop'

Write-Host "--- Stap 11: DHCP DNS opties bijwerken op SERVER1 ---" -ForegroundColor Yellow

# We gebruiken de DHCP-cmdlets op afstand gericht naar SERVER1
$dhcpServer = "server1.WS2-25-alexi.hogent"   # of gewoon "server1"
$scopeId    = "192.168.25.0"
$dns1       = "192.168.25.10"
$dns2       = "192.168.25.20"
$domainName = "WS2-25-alexi.hogent"

# Zorg dat de DhcpServer module beschikbaar is
Install-WindowsFeature RSAT-DHCP -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
Import-Module DhcpServer -ErrorAction Stop

# Controle: bestaat de scope op server1?
$scope = Get-DhcpServerv4Scope -ComputerName $dhcpServer -ScopeId $scopeId -ErrorAction SilentlyContinue
if (-not $scope) {
    Write-Warning "DHCP scope $scopeId is niet gevonden op $dhcpServer. DNS update wordt overgeslagen."
    return
}

Write-Host "Stel DHCP Option 6 (DNS servers) op $dhcpServer in op: $dns1, $dns2" -ForegroundColor Cyan
Set-DhcpServerv4OptionValue -ComputerName $dhcpServer `
    -ScopeId   $scopeId `
    -DnsServer $dns1, $dns2 `
    -DnsDomain $domainName

Write-Host "DHCP DNS servers succesvol bijgewerkt op $dhcpServer." -ForegroundColor Green
