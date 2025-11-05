# Client: zet auto DNS-registratie UIT (opdracht-eis)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

Write-Host "--- Client: auto DNS-registratie uitschakelen ---"
$ifs = Get-DnsClient | Where-Object { $_.InterfaceAlias -ne 'Loopback Pseudo-Interface 1' }
foreach ($i in $ifs) {
  Set-DnsClient -InterfaceIndex $i.InterfaceIndex -RegisterThisConnectionsAddress $false
}
# (optioneel) even tonen ter controle
Get-DnsClient | Select-Object InterfaceAlias, RegisterThisConnectionsAddress

# 10_configure_client.ps1

# --== CONFIGURATIE VARIABELEN ==--
$dnsServer1 = "192.168.25.10"
$adapterName = "Ethernet 2"
$domainName = "WS2-25-alexi.hogent"
$domainUser = "ALEXI\admin1"
$domainPwd = ConvertTo-SecureString "P@ssw0rdVoorHerstel!" -AsPlainText -Force
# --===========================--

# --- STAP 1: Netwerkconfiguratie ---
Write-Host "--- Stap 1: Netwerkconfiguratie voor client... ---" -ForegroundColor Green
# De client krijgt zijn IP via DHCP, dus we stellen alleen de DNS in.
Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $dnsServer1
Start-Sleep -Seconds 10 # Wacht tot DNS-instellingen zijn toegepast

# --- STAP 2: Domein join ---
Write-Host "--- Stap 2: Client toevoegen aan domein $domainName... ---" -ForegroundColor Green
$computerInfo = Get-ComputerInfo
if ($computerInfo.Domain -ne $domainName.ToUpper()) {
    Write-Host "Client wordt toegevoegd aan het domein (vereist herstart)..."
    $cred = New-Object System.Management.Automation.PSCredential($domainUser, $domainPwd)
    Add-Computer -DomainName $domainName -Credential $cred -Force
    Write-Host "Client is succesvol lid gemaakt van het domein. De herstart wordt door Vagrant afgehandeld."
} else {
    Write-Host "Client is al lid van het domein."
}

# --- STAP 3: RSAT en SSMS installeren ---
Write-Host "--- Stap 3: RSAT en SSMS installeren... ---" -ForegroundColor Green

# Installeer RSAT tools
Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"

# Installeer SSMS
# Voor SSMS gebruiken we de Chocolatey package manager, die is handig voor dit soort installaties.
# Eerst Chocolatey installeren als het er nog niet is.
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# SSMS installeren
choco install sql-server-management-studio -y
