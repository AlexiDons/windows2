Write-Host "--- STAP 9.1: DNS secundaire zones configureren op server2 ---"

# --== CONFIGURATIE VARIABELEN ==--
$domainName  = "WS2-25-alexi.hogent"
$forwardZone = $domainName
$reverseZone = "25.168.192.in-addr.arpa"
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

# Zorg dat de lokale resolver server1 dan server2 gebruikt
try {
    $nic = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | Select-Object -First 1
    if ($nic) {
        $desired = @($primaryIP, "192.168.25.20")
        if (@($nic.ServerAddresses) -ne $desired) {
            Set-DnsClientServerAddress -InterfaceIndex $nic.InterfaceIndex -ServerAddresses $desired | Out-Null
        }
    }
} catch {}

Write-Host "--- Installatie van SQL Server 2022 vanaf ISO ---"

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
    Write-Host "SQL Server ISO niet gevonden. Installatie overgeslagen."
}

# === SQL 2022 post-config ===
$ErrorActionPreference = 'Stop'

# Vind instance key
$instKey  = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
$instName = (Get-ItemProperty $instKey -ErrorAction SilentlyContinue).MSSQLSERVER
if (-not $instName) {
  $instName = (Get-ItemProperty $instKey).PSObject.Properties |
              Where-Object { $_.Name -ne 'MSSQLSERVER' } |
              Select-Object -ExpandProperty Value -First 1
}
$rootKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instName"

# Mixed mode aan + TCP 1433 vastzetten
Set-ItemProperty -Path "$rootKey\MSSQLServer" -Name "LoginMode" -Value 2
Set-ItemProperty -Path "$rootKey\MSSQLServer\SuperSocketNetLib\Tcp" -Name "Enabled" -Value 1
New-Item -Path "$rootKey\MSSQLServer\SuperSocketNetLib\Tcp\IPAll" -Force | Out-Null
Set-ItemProperty -Path "$rootKey\MSSQLServer\SuperSocketNetLib\Tcp\IPAll" -Name "TcpDynamicPorts" -Value ""
Set-ItemProperty -Path "$rootKey\MSSQLServer\SuperSocketNetLib\Tcp\IPAll" -Name "TcpPort" -Value "1433"

# Firewall voor SQL
New-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -Profile Domain -ErrorAction SilentlyContinue | Out-Null

# SQL service herstarten
$svc = Get-Service | Where-Object { $_.Name -match '^MSSQL(\$|SERVER)' } | Select-Object -First 1
if ($svc) { Restart-Service $svc.Name -Force } else { Write-Host "SQL service niet gevonden"; }

# T-SQL helper via .NET (geen sqlcmd nodig)
function Invoke-Tsql($query){
  $cn = New-Object System.Data.SqlClient.SqlConnection "Server=localhost;Integrated Security=true;Database=master;"
  $cn.Open()
  $cmd = $cn.CreateCommand()
  $cmd.CommandTimeout = 60
  $cmd.CommandText = $query
  [void]$cmd.ExecuteNonQuery()
  $cn.Close()
}

# SA wachtwoord + AD login als sysadmin + testdatabase
$saPwd = "S@feSqlP4ss!"   # <-- indien gewenst aanpassen
$tsql = @"
IF (SELECT is_disabled FROM sys.sql_logins WHERE name = N'sa') = 1
    ALTER LOGIN [sa] ENABLE;
ALTER LOGIN [sa] WITH PASSWORD = N'$saPwd';

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'ALEXI\Administrator')
    CREATE LOGIN [ALEXI\Administrator] FROM WINDOWS;

IF NOT EXISTS (
    SELECT 1 FROM sys.server_role_members 
    WHERE role_principal_id = SUSER_ID('sysadmin') 
      AND member_principal_id = SUSER_ID(N'ALEXI\Administrator')
)
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [ALEXI\Administrator];

IF DB_ID(N'LabTest') IS NULL
    CREATE DATABASE [LabTest];
"@
Invoke-Tsql $tsql

Write-Host "SQL post-config klaar: Mixed Mode, TCP 1433, SA set, ALEXI\Administrator = sysadmin, LabTest aangemaakt."

