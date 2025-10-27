# Wacht tot AD volledig operationeel is
$maxAttempts = 30
$attempt = 0

Write-Host "Wachten tot Active Directory volledig operationeel is..."

while ($attempt -lt $maxAttempts) {
    $attempt++
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Host "AD is operationeel: $($domain.DNSRoot)"
        break
    }
    catch {
        Write-Host "Poging $attempt/$maxAttempts - wacht 10 seconden..."
        Start-Sleep -Seconds 10
    }
}

if ($attempt -eq $maxAttempts) {
    Write-Error "Timeout: AD niet operationeel"
    exit 1
}

# --- STAP 4.2: INSTALLEER OVERIGE FEATURES (DHCP, CA, WEB) ---
Write-Host "--- Stap 4.2: Installatie van overige features (DHCP, Web, CA)... ---" -ForegroundColor Green
Install-WindowsFeature -Name DHCP, Web-Server, ADCS-Cert-Authority, ADCS-Web-Enrollment -IncludeManagementTools
Write-Host "Overige features zijn geïnstalleerd."

# --- STAP 4.3: CONFIGUREER CERTIFICATION AUTHORITY (CA) ---
Write-Host "--- Stap 4.3: Basisconfiguratie van de CA wordt uitgevoerd... ---" -ForegroundColor Green
$domainInfo = Get-ADDomain

# OPMERKING: De opdracht is tegenstrijdig.
# Het vraagt een "automatisch vertrouwde" CA, maar ook een "GPO" om dit te doen.
# Een EnterpriseRootCA is automatisch vertrouwd in het domein (zonder GPO).
# Een StandaloneRootCA is niet automatisch vertrouwd en VEREIST een GPO.
# Omdat er geen ingebouwde PowerShell cmdlet is om een cert aan een GPO toe te voegen,
# kiezen we voor EnterpriseRootCA om het hoofddoel (automatisch vertrouwd) te bereiken.
Install-AdcsCertificationAuthority -CAType EnterpriseRootCA `
    -CACommonName "$($domainInfo.NetBIOSName)-CA" `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -Force
    
# Configureer Web Enrollment (vereist voor de opdracht)
Install-AdcsWebEnrollment -Force

Write-Host "CA is geconfigureerd. Wacht 15 seconden tot services en regels geregistreerd zijn..."
Start-Sleep -Seconds 15

# --- STAP 4.4: CONFIGUREER SERVICE FIREWALL REGELS ---
Write-Host "--- Stap 4.4: Firewall regels voor services activeren... ---" -ForegroundColor Cyan
Enable-NetFirewallRule -DisplayGroup "Active Directory Domain Services"
Enable-NetFirewallRule -DisplayGroup "DNS Service"
Enable-NetFirewallRule -DisplayGroup "DHCP Server"
Enable-NetFirewallRule -DisplayGroup "World Wide Web Services (HTTP Traffic-In)"
Enable-NetFirewallRule -DisplayGroup "Active Directory Certificate Services"
Write-Host "Service firewall regels zijn geactiveerd."