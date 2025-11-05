# 09_configure_server2_roles.ps1
# Server2: DNS Secondary (CUI-style) + SQL Server 2022 install from ISO

Write-Host "--- STAP 9.1: DNS secundaire zones configureren op server2 ---" -ForegroundColor Green

# === Vars ===
$domainName  = "WS2-25-alexi.hogent"
$forwardZone = $domainName
$reverseZone = "25.168.192.in-addr.arpa"   # voor 192.168.25.0/24
$primaryIP   = "192.168.25.10"

# 1) Installeer DNS-rol (zoals CUI)
Install-WindowsFeature DNS -IncludeManagementTools | Out-Null

# 2) Voeg secondary forward zone toe (CUI)
if ($null -eq (Get-DnsServerZone -Name $forwardZone -ErrorAction SilentlyContinue)) {
    Add-DnsServerSecondaryZone -Name $forwardZone -ZoneFile "$forwardZone.secondary.dns" -MasterServers $primaryIP | Out-Null
    Write-Host "Secundaire forward zone '$forwardZone' aangemaakt."
} else {
    Write-Host "Secundaire forward zone '$forwardZone' bestaat al."
}

# 3) Voeg secondary reverse zone toe (CUI)
if ($null -eq (Get-DnsServerZone -Name $reverseZone -ErrorAction SilentlyContinue)) {
    Add-DnsServerSecondaryZone -Name $reverseZone -ZoneFile "$reverseZone.secondary.dns" -MasterServers $primaryIP | Out-Null
    Write-Host "Secundaire reverse zone '$reverseZone' aangemaakt."
} else {
    Write-Host "Secundaire reverse zone '$reverseZone' bestaat al."
}

# 4) Firewall: DNS + SQL (behoud jouw regel)
Enable-NetFirewallRule -DisplayGroup "DNS Server" -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -ErrorAction SilentlyContinue | Out-Null

# (optioneel) Zorg dat de lokale resolver server1 dan server2 gebruikt
try {
    $nic = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | Select-Object -First 1
    if ($nic) {
        $desired = @($primaryIP, "192.168.25.20")
        if (@($nic.ServerAddresses) -ne $desired) {
            Set-DnsClientServerAddress -InterfaceIndex $nic.InterfaceIndex -ServerAddresses $desired | Out-Null
        }
    }
} catch {}

# === STAP 9.2: SQL Server 2022 vanaf ISO (ongemoeid gelaten) ===
Write-Host "--- Installatie van SQL Server 2022 vanaf ISO... ---" -ForegroundColor Green

# Zoek de drive letter van de gemounte ISO
$drive = Get-Volume | Where-Object { $_.FileSystemLabel -like "*SQL*" } | Select-Object -First 1

if ($drive) {
    $setupPath = Join-Path -Path ($drive.DriveLetter + ":\") -ChildPath "setup.exe"
    Write-Host "SQL Server setup gevonden op: $setupPath"

    # Stille installatie commando
    $arguments = "/Q", "/ACTION=Install", "/FEATURES=SQLENGINE", "/INSTANCENAME=MSSQLSERVER", "/SQLSVCACCOUNT=`"NT AUTHORITY\System`"", "/SQLSYSADMINACCOUNTS=`"BUILTIN\Administrators`"", "/AGTSVCACCOUNT=`"NT AUTHORITY\Network Service`"", "/IACCEPTSQLSERVERLICENSETERMS"
    
    Start-Process -FilePath $setupPath -ArgumentList $arguments -Wait

    Write-Host "SQL Server 2022 installatie is voltooid."
} else {
    Write-Host "SQL Server ISO niet gevonden. Installatie overgeslagen." -ForegroundColor Red
}
