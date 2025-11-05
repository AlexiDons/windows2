# scripts/06_configure_dns.ps1  (patch: no -DynamicUpdate on ConvertTo-; set it with Set-DnsServerPrimaryZone)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# --- wait for ADWS/DNS ---
Write-Host "Wachten op ADWS..."
$tries = 0
do { $tries++; $ad = Get-ADDomain -ErrorAction SilentlyContinue; if ($ad) { break }; Start-Sleep 5 } while ($tries -lt 30)
Write-Host "Wachten op DNS service..."
$svc = Get-Service DNS -ErrorAction SilentlyContinue
if ($null -eq $svc -or $svc.Status -ne 'Running') { Start-Service DNS }
Start-Sleep -Seconds 2

Write-Host "--- Step 6 (server1): DNS primary configureren ---"

# === Vars ===
$DomainName = (Get-ADDomain).DNSRoot
$ForestRoot = (Get-ADForest).RootDomain
$Server1    = "server1"
$Server2    = "server2"
$IP1        = "192.168.25.10"
$IP2        = "192.168.25.20"

# === Derived ===
$Octets      = $IP1.Split('.')
$RevZone     = "$($Octets[2]).$($Octets[1]).$($Octets[0]).in-addr.arpa"   # 25.168.192.in-addr.arpa
$NetworkId   = "$($Octets[0]).$($Octets[1]).$($Octets[2]).0/24"           # 192.168.25.0/24
$FQDN1       = "$Server1.$DomainName"
$FQDN2       = "$Server2.$DomainName"

# 0) DNS-client naar zichzelf
$nic = Get-DnsClientServerAddress -AddressFamily IPv4 | ? { $_.InterfaceAlias -like 'Ethernet*' } | Select -First 1
if ($nic) { Set-DnsClientServerAddress -InterfaceIndex $nic.InterfaceIndex -ServerAddresses 127.0.0.1 | Out-Null }

# 1) DNS role/service
if (-not (Get-WindowsFeature DNS).Installed) { Install-WindowsFeature DNS -IncludeManagementTools | Out-Null }
if ((Get-Service DNS -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service DNS }

# 2) DNS application partitions (idempotent) + enlist
dnscmd /CreateBuiltinDirectoryPartitions /Domain  | Out-Null
dnscmd /CreateBuiltinDirectoryPartitions /Forest  | Out-Null
$domPart = "DomainDnsZones.$DomainName"
$forPart = "ForestDnsZones.$ForestRoot"
# wait till visible
$deadline = (Get-Date).AddMinutes(2)
do { $dp = Get-DnsServerDirectoryPartition -Name $domPart -ErrorAction SilentlyContinue; if ($dp){break}; Start-Sleep 2 } while ((Get-Date) -lt $deadline)
$deadline = (Get-Date).AddMinutes(2)
do { $fp = Get-DnsServerDirectoryPartition -Name $forPart -ErrorAction SilentlyContinue; if ($fp){break}; Start-Sleep 2 } while ((Get-Date) -lt $deadline)
# enlist (idempotent)
dnscmd /EnlistDirectoryPartition $domPart | Out-Null
dnscmd /EnlistDirectoryPartition $forPart | Out-Null
Restart-Service DNS -Force
Start-Sleep -Seconds 5

# 3) Firewall
Enable-NetFirewallRule -DisplayGroup "DNS Server" -ErrorAction SilentlyContinue | Out-Null

# 4) Forward zone (AD, Secure)
if (-not (Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue)) {
  Add-DnsServerPrimaryZone -Name $DomainName -ReplicationScope Domain -DynamicUpdate Secure | Out-Null
  Write-Host "Forward zone $DomainName aangemaakt."
} else { Write-Host "Forward zone $DomainName bestaat al." }

# 5) Reverse zone
$revObj = Get-DnsServerZone -Name $RevZone -ErrorAction SilentlyContinue
if ($null -eq $revObj) {
  # direct AD-integrated (nu partitions/enlist OK zijn)
  Add-DnsServerPrimaryZone -NetworkId $NetworkId -ReplicationScope Domain -DynamicUpdate Secure | Out-Null
  Write-Host "Reverse zone $RevZone aangemaakt als AD-integrated."
} elseif (-not $revObj.IsDsIntegrated) {
  # PATCH: ConvertTo- zonder -DynamicUpdate; daarna Set- om dynamic updates te forceren
  ConvertTo-DnsServerPrimaryZone -Name $RevZone -ReplicationScope Domain | Out-Null
  Set-DnsServerPrimaryZone -Name $RevZone -DynamicUpdate Secure | Out-Null
  Write-Host "Reverse zone $RevZone geconverteerd naar AD-integrated + Secure updates."
} else {
  # zone is al AD-integrated; zorg dat updates Secure zijn
  Set-DnsServerPrimaryZone -Name $RevZone -DynamicUpdate Secure | Out-Null
  Write-Host "Reverse zone $RevZone bestaat al (AD-integrated)."
}

# 6) Records
if (-not (Get-DnsServerResourceRecord -ZoneName $DomainName -Name $Server1 -ErrorAction SilentlyContinue | ? RecordType -eq 'A')) {
  Add-DnsServerResourceRecordA -ZoneName $DomainName -Name $Server1 -IPv4Address $IP1 -CreatePtr | Out-Null
  Write-Host "A(+PTR) server1 toegevoegd."
} else { Write-Host "A-record server1 bestaat al." }

if (-not (Get-DnsServerResourceRecord -ZoneName $DomainName -Name $Server2 -ErrorAction SilentlyContinue | ? RecordType -eq 'A')) {
  Add-DnsServerResourceRecordA -ZoneName $DomainName -Name $Server2 -IPv4Address $IP2 | Out-Null
  Write-Host "A server2 toegevoegd."
} else { Write-Host "A-record server2 bestaat al." }

$Oct1 = ($IP1.Split('.')[3])
if (-not (Get-DnsServerResourceRecord -ZoneName $RevZone -Name $Oct1 -ErrorAction SilentlyContinue | ? RecordType -eq 'PTR')) {
  Add-DnsServerResourceRecordPtr -ZoneName $RevZone -Name $Oct1 -PtrDomainName $FQDN1 | Out-Null
  Write-Host "PTR $IP1 -> $FQDN1 toegevoegd."
}
$Oct2 = ($IP2.Split('.')[3])
if (-not (Get-DnsServerResourceRecord -ZoneName $RevZone -Name $Oct2 -ErrorAction SilentlyContinue | ? RecordType -eq 'PTR')) {
  Add-DnsServerResourceRecordPtr -ZoneName $RevZone -Name $Oct2 -PtrDomainName $FQDN2 | Out-Null
  Write-Host "PTR $IP2 -> $FQDN2 toegevoegd."
}

# 7) Zone transfers + notify naar server2
if (Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue) {
  Set-DnsServerPrimaryZone -Name $DomainName -SecureSecondaries TransferToSecureServers -SecondaryServers $IP2 -Notify NotifyServers -NotifyServers $IP2 -PassThru | Out-Null
  Write-Host "Zone transfers ingesteld voor $DomainName."
}
if (Get-DnsServerZone -Name $RevZone -ErrorAction SilentlyContinue) {
  Set-DnsServerPrimaryZone -Name $RevZone -SecureSecondaries TransferToSecureServers -SecondaryServers $IP2 -Notify NotifyServers -NotifyServers $IP2 -PassThru | Out-Null
  Write-Host "Zone transfers ingesteld voor $RevZone."
}

Write-Host "DNS primary (AD-integrated) klaar op server1."
