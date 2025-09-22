# --== CONFIGURATIE VARIABELEN ==--
# Hier kun je eenvoudig de basisinstellingen aanpassen.
$ipaddress = "192.168.25.10"
# --===========================--

Start-Sleep -Seconds 5
Write-Host "Starten van netwerkconfiguratie voor server1..."

# De tweede netwerkadapter in een Windows VM heet bijna altijd "Ethernet 2"
$adapterName = "Ethernet 2"
$netAdapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue

# Controleer of de adapter is gevonden
if ($netAdapter) {
    Write-Host "Adapter '$($adapterName)' gevonden. Bezig met configureren..."

    # Stap 1: Verwijder eerst eventuele bestaande IP-adressen
    Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false

    # Stap 2: Stel het nieuwe statische IP-adres in met de variabele
    New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress $ipaddress -PrefixLength 24
    
    # Stap 3: Stel de DNS-server in
    Set-DnsClientServerAddress -InterfaceIndex $netAdapter.ifIndex -ServerAddresses "127.0.0.1"

    Write-Host @"
    +----------------------------------------------------------------------+
    |            ___                                                       |
    |  /\  |    |__  \_/ |                                                 |
    | /~~\ |___ |___ / \ |                                                 |
    +----------------------------------------------------------------------+
    |                                                                      |
    |  >> Netwerkconfiguratie is [ VOLTOOID ]                              |
    |  >> IP: $ipadress                                                |
    |                                                                      |
    +----------------------------------------------------------------------+
"@

} else {
    # Als de adapter niet wordt gevonden, stopt het script met een duidelijke melding.
    Write-Host "!!! FOUT: Kon netwerkadapter met de naam '$($adapterName)' niet vinden. Script wordt gestopt. !!!"
    exit 1
}