Write-Host "--- Stap 5: DHCP Server configureren... ---" -ForegroundColor Green
$domainName = "WS2-25-alexi.hogent"
$scopeID = "192.168.25.0"
$scopeName = "WS2_Scope"
$startRange = "192.168.25.50"
$endRange = "192.168.25.150"
$excludedStart = "192.168.25.101"
$excludedEnd = "192.168.25.150"
$router = "192.168.25.1" # Aanname, de PDF specificeert dit niet. Pas aan indien nodig.
$dnsServer = "192.168.25.10"

# Authorize DHCP Server in Active Directory (Idempotent check)
if (-not (Get-DhcpServerInDC -ErrorAction SilentlyContinue | Where-Object { $_.DnsName -eq "server1.$domainName" })) {
    Write-Host "DHCP Server autoriseren in AD..."
    Add-DhcpServerInDC -DnsName "server1.$domainName"
} else {
    Write-Host "DHCP Server is al geautoriseerd in AD."
}

# Create the scope if it doesn't exist
if (-not (Get-DhcpServerv4Scope -ComputerName "server1.$domainName" -ScopeId $scopeID -ErrorAction SilentlyContinue)) {
    Write-Host "DHCP Scope $scopeName wordt aangemaakt..."
    Add-DhcpServerv4Scope -ComputerName "server1.$domainName" `
        -Name $scopeName `
        -StartRange $startRange `
        -EndRange $endRange `
        -SubnetMask 255.255.255.0
    
    # Add Exclusions
    Add-DhcpServerv4ExclusionRange -ComputerName "server1.$domainName" `
        -ScopeId $scopeID `
        -StartRange $excludedStart `
        -EndRange $excludedEnd
    
    # Set Scope Options
    Set-DhcpServerv4OptionValue -ComputerName "server1.$domainName" `
        -ScopeId $scopeID -OptionId 3 -Value $router # Router
    Set-DhcpServerv4OptionValue -ComputerName "server1.$domainName" `
        -ScopeId $scopeID -OptionId 6 -Value $dnsServer # DNS Server
    Set-Dhcpserverv4OptionValue -ComputerName "server1.$domainName" `
        -ScopeId $scopeID -OptionId 15 -Value $domainName # Domain Name
    
    Write-Host "DHCP Scope $scopeName is geconfigureerd."
} else {
    Write-Host "DHCP Scope $scopeName is al geconfigureerd."
}