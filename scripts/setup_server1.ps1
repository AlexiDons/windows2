# setup_server1.ps1

# --== CONFIGURATIE VARIABELEN ==--
$ipaddress = "192.168.25.10"
$domainName = "WS2-25-alexi.hogent"
$safeModePassword = "P@ssw0rdVoorHerstel!"
# --===========================--

# --- IDEMPOTENTE NETWERKCONFIGURATIE ---
Write-Host "Controleren van netwerkconfiguratie..."
$adapterName = "Ethernet 2"
$netAdapter = Get-NetAdapter -Name $adapterName
$currentIP = (Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress

if ($currentIP -ne $ipaddress) {
    Write-Host "Netwerkconfiguratie is incorrect. Bezig met instellen..."
    Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
    New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress $ipaddress -PrefixLength 24
    Set-DnsClientServerAddress -InterfaceIndex $netAdapter.ifIndex -ServerAddresses "127.0.0.1"
    
    Write-Host @"
    +----------------------------------------------------------------------+
    |            ___                                                       |
    |  /\  |    |__  \_/ |                                                 |
    | /~~\ |___ |___ / \ |                                                 |
    +----------------------------------------------------------------------+
    |                                                                      |
    |  >> Netwerkconfiguratie is [ VOLTOOID ]                              |
    |  >> IP: $ipaddress                                                |
    |                                                                      |
    +----------------------------------------------------------------------+
"@
} else {
    Write-Host "Netwerk is al correct geconfigureerd."
}


# --- IDEMPOTENTE ACTIVE DIRECTORY INSTALLATIE ---
Write-Host "Controleren van Active Directory status..."

$adRole = Get-WindowsFeature -Name AD-Domain-Services
if (-not $adRole.Installed) {
    Write-Host "Active Directory rol is niet geïnstalleerd. Bezig met installatie..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    
    $securePassword = ConvertTo-SecureString $safeModePassword -AsPlainText -Force
    
    Install-ADDSForest -DomainName $domainName `
        -DomainNetBiosName "ALEXI" `
        -DomainMode Win2025 `
        -ForestMode Win2025 `
        -InstallDns `
        -SafeModeAdministratorPassword $securePassword `
        -NoRebootOnCompletion "False"`
        -Force
        
    Write-Host "Active Directory is geïnstalleerd. Server wordt herstart."
} else {
    Write-Host "Active Directory rol is al geïnstalleerd."
}