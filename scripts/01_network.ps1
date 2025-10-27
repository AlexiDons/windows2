# --== CONFIGURATIE VARIABELEN ==--
$ipaddress = "192.168.25.10"
$adapterName = "Ethernet 2"
# --===========================--

# --- STAP 1.1: IDEMPOTENTE BASIS FIREWALL CONFIGURATIE ---
Write-Host "--- Stap 1.1: Controleren van basis firewall regels... ---" -ForegroundColor Cyan

if (-not (Get-NetFirewallRule -DisplayName "Vagrant WinRM" -ErrorAction SilentlyContinue)) {
    Write-Host "Firewall regel 'Vagrant WinRM' niet gevonden. Wordt aangemaakt..."
    New-NetFirewallRule -DisplayName "Vagrant WinRM" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any
} else {
    Write-Host "Firewall regel 'Vagrant WinRM' is al aanwezig."
}

if (-not (Get-NetFirewallRule -DisplayName "Vagrant SSH" -ErrorAction SilentlyContinue)) {
    Write-Host "Firewall regel 'Vagrant SSH' niet gevonden. Wordt aangemaakt..."
    New-NetFirewallRule -DisplayName "Vagrant SSH" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any
} else {
    Write-Host "Firewall regel 'Vagrant SSH' is al aanwezig."
}
Write-Host "Basis firewall regels zijn gecontroleerd."


# --- STAP 1.2: IDEMPOTENTE NETWERKCONFIGURATIE ---
Write-Host "--- Stap 1.2: Controleren van netwerkconfiguratie... ---" -ForegroundColor Green

$netAdapter = Get-NetAdapter -Name $adapterName
$ipConfig = Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
$dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

$currentIP = $ipConfig.IPAddress
$currentDns = $dnsConfig.ServerAddresses

# We controleren zowel het IP-adres als de DNS-instelling
if ($currentIP -eq $ipaddress -and $currentDns -contains "127.0.0.1") {
    Write-Host "Netwerk is al correct geconfigureerd."
} else {
    Write-Host "Netwerkconfiguratie is incorrect. Bezig met instellen..."
    
    # Verwijder bestaande IP-adressen op deze adapter
    if ($ipConfig) {
        $ipConfig | Remove-NetIPAddress -Confirm:$false
    }
    
    # Stel het nieuwe IP-adres in
    New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress $ipaddress -PrefixLength 24
    
    # Stel het DNS-adres in
    Set-DnsClientServerAddress -InterfaceIndex $netAdapter.ifIndex -ServerAddresses "127.0.0.1"
    
    # Toon jouw ASCII-art template
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
}