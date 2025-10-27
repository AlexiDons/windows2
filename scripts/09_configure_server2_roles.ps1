# --- STAP 9.1: Installeer DNS Feature ---
Write-Host "--- Stap 9.1: DNS-rol installeren... ---" -ForegroundColor Green
Install-WindowsFeature -Name DNS -IncludeManagementTools

# --- STAP 9.2: Configureer Secundaire DNS Zones ---
Write-Host "--- Stap 9.2: Secundaire DNS-zones configureren... ---" -ForegroundColor Green
$domainZone = "WS2-25-alexi.hogent"
$reverseZone = "25.168.192.in-addr.arpa"
$primaryServer = "192.168.25.10"
$server2Name = "server2.$domainZone"

# Voeg de primaire en reverse zones toe als secundaire zones
if (-not (Get-DnsServerZone -Name $domainZone -ComputerName "server2" -ErrorAction SilentlyContinue)) {
    Add-DnsServerSecondaryZone -Name $domainZone -ZoneFile "$domainZone.dns" -MasterServers $primaryServer
    Write-Host "Secundaire zone $domainZone toegevoegd."
}
if (-not (Get-DnsServerZone -Name $reverseZone -ComputerName "server2" -ErrorAction SilentlyContinue)) {
    Add-DnsServerSecondaryZone -Name $reverseZone -ZoneFile "$reverseZone.dns" -MasterServers $primaryServer
    Write-Host "Secundaire zone $reverseZone toegevoegd."
}

# --- STAP 9.3: Configureer server1 (op afstand) om Zone Transfers toe te staan ---
Write-Host "--- Stap 9.3: server1 op afstand configureren voor zone transfers... ---" -ForegroundColor Cyan
$cred = New-Object System.Management.Automation.PSCredential("ALEXI\Administrator", (ConvertTo-SecureString "P@ssw0rdVoorHerstel!" -AsPlainText -Force))
$s = New-PSSession -ComputerName "server1.$domainZone" -Credential $cred

# Voeg server2 toe als Name Server (NS) record op server1
Invoke-Command -Session $s -ScriptBlock {
    param($domainZone, $reverseZone, $server2Name)
    Write-Host "  [Remote server1]: server2 toevoegen als NS-record..."
    Add-DnsServerResourceRecord -NS -Name "." -ZoneName $domainZone -NameServer $server2Name -ComputerName "server1"
    Add-DnsServerResourceRecord -NS -Name "." -ZoneName $reverseZone -NameServer $server2Name -ComputerName "server1"
    
    # Sta zone transfers toe naar servers die in het NS-record staan (dus server1 en server2)
    Write-Host "  [Remote server1]: Zone transfers instellen op 'TransferToSecureServers'..."
    Set-DnsServerPrimaryZone -Name $domainZone -SecureSecondaries TransferToSecureServers -ComputerName "server1"
    Set-DnsServerPrimaryZone -Name $reverseZone -SecureSecondaries TransferToSecureServers -ComputerName "server1"
} -ArgumentList $domainZone, $reverseZone, $server2Name

Remove-PSSession $s
Write-Host "Zone transfer configuratie voltooid."

# --- STAP 9.4: Installeer MS SQL Server 2022 ---
Write-Host "--- Stap 9.4: Installatie van MS SQL Server 2022... ---" -ForegroundColor Green
$isoName = "enu_sql_server_2022_standard_edition_x64_dvd_43079f69.iso"
$isoPath = "C:\vagrant\$isoName"

if (-not (Test-Path $isoPath)) {
    Write-Error "SQL ISO niet gevonden op $isoPath. Zorg ervoor dat '$isoName' in je Vagrant-projectmap staat."
} else {
    Write-Host "SQL ISO gevonden. Bezig met mounten..."
    $mount = Mount-DiskImage -ImagePath $isoPath -PassThru
    $drive = ($mount | Get-Volume).DriveLetter
    $setupPath = "$($drive):\setup.exe"
    
    Write-Host "Silent installatie van SQL Server wordt gestart (dit kan lang duren)..."
    # Argumenten voor een silent installatie die AD-groepen (Domain Admins) als SysAdmin instelt
    $args = "/q /ACTION=Install /FEATURES=SQLENGINE `
        /INSTANCENAME=MSSQLSERVER `
        /SQLSVCACCOUNT=""NT AUTHORITY\System"" `
        /SQLSYSADMINACCOUNTS=""BUILTIN\Administrators"",""ALEXI\Domain Admins"" `
        /IACCEPTSQLSERVERLICENSETERMS"
        
    Start-Process -FilePath $setupPath -ArgumentList $args -Wait
    
    Write-Host "SQL Server installatie voltooid. ISO wordt gedemount..."
    Dismount-DiskImage -ImagePath $isoPath
}

# --- STAP 9.5: Firewall configureren ---
Write-Host "--- Stap 9.5: Firewall configureren voor DNS en SQL... ---" -ForegroundColor Cyan
Enable-NetFirewallRule -DisplayGroup "DNS Service"
New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow

Write-Host "--- VOLLEDIGE PROVISIONING SERVER2 VOLTOOID ---" -ForegroundColor Magenta