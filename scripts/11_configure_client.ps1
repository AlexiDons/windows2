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
$domainName = "WS2-25-alexi.hogent"
$domainUser = "ALEXI\admin1"
$domainPwd = ConvertTo-SecureString "P@ssw0rdVoorHerstel!" -AsPlainText -Force
# --===========================--

# --- STAP 1: Domein join ---
Write-Host "--- Stap 1: Client toevoegen aan domein $domainName... ---"
$computerInfo = Get-ComputerInfo
if ($computerInfo.Domain -ne $domainName.ToUpper()) {
    Write-Host "Client wordt toegevoegd aan het domein (vereist herstart)..."
    $cred = New-Object System.Management.Automation.PSCredential($domainUser, $domainPwd)
    Add-Computer -DomainName $domainName -Credential $cred -Force
    Write-Host "Client is succesvol lid gemaakt van het domein. De herstart wordt door Vagrant afgehandeld."
} else {
    Write-Host "Client is al lid van het domein."
}

# --- STAP 2: RSAT en SSMS installeren (CORRECTIE) ---
Write-Host "--- Stap 2: RSAT en SSMS installeren... ---"

# Installeer RSAT tools (alle tools die nodig zijn voor de opdracht)
$rsatTools = @(
    "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
    "Rsat.Dns.Tools~~~~0.0.1.0",
    "Rsat.Dhcp.Tools~~~~0.0.1.0",
    "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0"
)

Write-Host "Bezig met installeren van de volgende RSAT tools:"

# --- FIX: Loop door de tools en installeer ze één voor één ---
try {
    foreach ($tool in $rsatTools) {
        Write-Host "- Bezig met installeren van: $tool"
        Add-WindowsCapability -Online -Name $tool
    }
    Write-Host "Alle RSAT tools succesvol geïnstalleerd."
} catch {
    Write-Error "Fout bij het installeren van RSAT tool '$tool': $_"
}


# Installeer SSMS
# Voor SSMS gebruiken we de Chocolatey package manager, die is handig voor dit soort installaties.
# Eerst Chocolatey installeren als het er nog niet is.
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Chocolatey wordt geïnstalleerd..."
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
} else {
    Write-Host "Chocolatey is al geïnstalleerd."
}

# SSMS installeren
Write-Host "SSMS wordt geïnstalleerd via Chocolatey"
choco install sql-server-management-studio -y

Write-Host "Installatie van RSAT en SSMS is voltooid."

#===============================================================================
# Disable NAT adapter zodat alleen interne DNS gebruikt wordt
#===============================================================================
Write-Host "Final Step: Disabling NAT adapter 1 "

$internalPrefix = '192.168.25.'

# Zoek alle actieve adapters die GEEN IP in 192.168.25.x hebben (NAT / externe NICs)
$natAdapters = Get-NetAdapter |
    Where-Object { $_.Status -eq 'Up' } |
    Where-Object {
        -not (
            Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -like "$internalPrefix*" }
        )
    }

if ($natAdapters) {
    foreach ($nic in $natAdapters) {
        Write-Host "Disabling NAT adapter: $($nic.Name) ($($nic.InterfaceDescription))"
        Disable-NetAdapter -Name $nic.Name -Confirm:$false -ErrorAction SilentlyContinue
    }
    Write-Host "NAT adapter(s) uitgeschakeld. Client gebruikt nu enkel interne DNS."
}
else {
    Write-Host "Geen NAT adapter gevonden of al uitgeschakeld."
}
