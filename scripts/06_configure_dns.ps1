Write-Host "--- Stap 6: DNS Reverse Lookup Zone configureren... ---" -ForegroundColor Green
$domainName = "WS2-25-alexi.hogent"
$reverseZoneName = "25.168.192.in-addr.arpa"
$server1IP = "192.168.25.10"
$server1Hostname = "server1"

if (-not (Get-DnsServerZone -Name $reverseZoneName -ComputerName "server1.$domainName" -ErrorAction SilentlyContinue)) {
    Write-Host "DNS Reverse Lookup Zone $reverseZoneName wordt aangemaakt..."
    # Maak de zone en repliceer deze naar alle DNS-servers in het forest
    Add-DnsServerPrimaryZone -Name $reverseZoneName -ReplicationScope "Forest" -ComputerName "server1.$domainName"
    
    Write-Host "PTR record for $server1Hostname wordt aangemaakt..."
    # Maak het PTR record voor server1
    Add-DnsServerResourceRecord -Ptr -Name "10" -ZoneName $reverseZoneName -PtrDomainName "$server1Hostname.$domainName." -ComputerName "server1.$domainName"
    
    Write-Host "DNS Reverse Zone en PTR record zijn aangemaakt."
} else {
    Write-Host "DNS Reverse Lookup Zone $reverseZoneName bestaat al."
}