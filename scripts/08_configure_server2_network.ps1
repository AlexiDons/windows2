# --== CONFIGURATIE VARIABELEN ==--
$ipaddress = "192.168.25.20"
$gateway = "192.168.25.1" # Aanname, niet gespecificeerd in PDF
$dnsServer1 = "192.168.25.10" # Primaire DNS (server1)
$adapterName = "Ethernet 2"

$domainName = "WS2-25-alexi.hogent"
$domainUser = "ALEXI\admin1"
$domainPwd = ConvertTo-SecureString "P@ssw0rdVoorHerstel!" -AsPlainText -Force
# --===========================--

Write-Host "--- Stap 8.1: Netwerkconfiguratie voor server2... ---" -ForegroundColor Green

$netAdapter = Get-NetAdapter -Name $adapterName
$ipConfig = Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

# Idempotente netwerkconfiguratie
if ($ipConfig.IPAddress -ne $ipaddress) {
    Write-Host "IP-adres instellen op $ipaddress..."
    if ($ipConfig) { $ipConfig | Remove-NetIPAddress -Confirm:$false }
    New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress $ipaddress -PrefixLength 24 -DefaultGateway $gateway
    Set-DnsClientServerAddress -InterfaceIndex $netAdapter.ifIndex -ServerAddresses $dnsServer1
} else {
    Write-Host "Netwerk is al correct geconfigureerd."
}

# --- STAP 8.2: Server toevoegen aan het domein ---
Write-Host "--- Stap 8.2: Server2 toevoegen aan domein $domainName... ---" -ForegroundColor Green

$computerInfo = Get-ComputerInfo
if ($computerInfo.Domain -ne $domainName.ToUpper()) {
    Write-Host "Server wordt toegevoegd aan het domein (vereist herstart)..."
    $cred = New-Object System.Management.Automation.PSCredential($domainUser, $domainPwd)
    Add-Computer -DomainName $domainName -Credential $cred -Force
    Write-Host "Server is succesvol lid gemaakt van het domein. De herstart wordt door Vagrant afgehandeld."
} else {
    Write-Host "Server is al lid van het domein."
}