#<#
# 04_post_dc_config.ps1 — hardened

# - Waits for AD + PKI containers
# - Ensures ADCS role files are present, imports ADCSDeployment
# - Writes a minimal CAPolicy.inf for a root CA
# - Installs EnterpriseRootCA if running as Enterprise Admins, else StandaloneRootCA
# - Publishes/exports root cert; optionally enables auto-enrollment via GPO (only if domain context is good)
# #>

#$ErrorActionPreference = 'Stop'

# -------------------------
# Helpers
# -------------------------
#function Wait-ADReady {
#    param([int]$MaxSeconds = 600)
#    $sw = [Diagnostics.Stopwatch]::StartNew()
#    while ($sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
#        try {
#            Import-Module ActiveDirectory -ErrorAction Stop
#            $dc = Get-ADDomainController -Discover -ErrorAction Stop
#            Resolve-DnsName -Type SRV "_ldap._tcp.$($dc.Forest)" -ErrorAction Stop | Out-Null
#            if (Test-Path "\\$($dc.HostName)\SYSVOL") { return }
#        } catch { }
#        Start-Sleep -Seconds 5
#    }
#    throw "Timeout: AD not fully ready after $MaxSeconds seconds."
#}

#function Wait-ConfigNCReady {
#    param([int]$MaxSeconds = 300)
#    $sw = [Diagnostics.Stopwatch]::StartNew()
#    $configDN = (Get-ADRootDSE).configurationNamingContext
#    $pkiDN    = "CN=Public Key Services,CN=Services,$configDN"
#    $need     = @('AIA','Enrollment Services','Certificate Templates')
#    while ($sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
#        try {
#            Get-ADObject -Identity $pkiDN -ErrorAction Stop | Out-Null
#            $have = (Get-ADObject -LDAPFilter '(cn=*)' -SearchBase $pkiDN -SearchScope OneLevel).Name
#            if (@($need | Where-Object { $_ -notin $have }).Count -eq 0) { return }
#        } catch { }
#        Start-Sleep -Seconds 5
#    }
#    throw "Timeout: PKI containers in Configuration partition are not ready."
#}

#function Cleanup-CAArtifacts {
#    param([string]$CACommonName)
#    try {
#        $configDN = (Get-ADRootDSE).configurationNamingContext
#        $enrollDN = "CN=Enrollment Services,CN=Public Key Services,CN=Services,$configDN"
#        $objDN    = "CN=$CACommonName,$enrollDN"
#        try {
#            $old = Get-ADObject -Identity $objDN -ErrorAction Stop
#            if ($old) { Remove-ADObject -Identity $objDN -Confirm:$false -Recursive -ErrorAction SilentlyContinue }
#        } catch { }
#    } catch { }

#    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration'
#    if (Test-Path $regPath) {
#        Get-ChildItem $regPath -ErrorAction SilentlyContinue |
#            Where-Object { $_.PSChildName -eq $CACommonName } |
#            ForEach-Object { Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
#    }
#    foreach ($p in @('C:\Windows\System32\CertLog','C:\Windows\System32\CertSrv\CertEnroll')) {
#        if (Test-Path $p) { Remove-Item "$p\*" -Force -ErrorAction SilentlyContinue }
#    }
#}

#function Test-IsEnterpriseAdmin {
#    try {
#        $ea = Get-ADGroup 'Enterprise Admins' -ErrorAction Stop
#        return (Get-ADGroupMember $ea -Recursive |
#                Where-Object { $_.SamAccountName -ieq $env:USERNAME }).Count -gt 0
#    } catch { return $false }
#}

#function Ensure-ADCSDeploymentModule {
#    # Make sure role files exist and module can load
#    if (-not (Get-WindowsFeature ADCS-Cert-Authority).Installed) {
#        Install-WindowsFeature -Name ADCS-Cert-Authority, ADCS-Web-Enrollment -IncludeManagementTools | Out-Null
#    }
#    Import-Module ADCSDeployment -ErrorAction Stop
#}

# -------------------------
# Start
# -------------------------
#Write-Host "--- Stap 4.1: Wachten tot AD volledig operationeel is ---"
#Wait-ADReady
#Write-Host "AD/DC ready."

#Write-Host "--- Stap 4.2: Rollen & modules ---"
# IIS+WebEnrol + DHCP are typically installed earlier, but ensure ADCS files exist
#Ensure-ADCSDeploymentModule

# -------------------------
# CAPolicy.inf (recommended for root CA)
# -------------------------
#Write-Host "--- Stap 4.3: CAPolicy.inf voorbereiden ---"
#$capath = 'C:\Windows\CAPolicy.inf'
#$capolicy = @"
#[Version]
#Signature="\$Windows NT$"

#[Certsrv_Server]
#RenewalKeyLength=2048
#RenewalValidityPeriod=Years
#RenewalValidityPeriodUnits=5
#AlternateSignatureAlgorithm=1
#"@
#$capolicy | Set-Content -Path $capath -Encoding ASCII

# -------------------------
# CA Install
# -------------------------
#Write-Host "--- Stap 4.4: CA installatie ---"
#$caName = 'WS2CA'
#$ksp    = 'RSA#Microsoft Software Key Storage Provider'
#$caDB   = 'C:\Windows\System32\CertLog'
#$caLog  = 'C:\Windows\System32\CertLog'

#Wait-ConfigNCReady
#Cleanup-CAArtifacts -CACommonName $caName

#$isEA = $false
#try { $isEA = Test-IsEnterpriseAdmin } catch { $isEA = $false }

#if ($isEA) {
#    Write-Host "Context = Enterprise Admins → EnterpriseRootCA"
#    $attempts = 0
#    do {
#        $attempts++
#        try {
#            Install-AdcsCertificationAuthority `
#                -CAType EnterpriseRootCA `
#                -CACommonName $caName `
#                -CryptoProviderName $ksp `
#                -KeyLength 2048 `
#                -HashAlgorithmName SHA256 `
#                -ValidityPeriod Years `
#                -ValidityPeriodUnits 5 `
#                -DatabaseDirectory $caDB `
#                -LogDirectory $caLog `
#                -Force
#            break
#        } catch {
#            if ($_.Exception.Message -match '0x80072082' -and $attempts -lt 2) {
#                Write-Warning "Enterprise install hit ERROR_DS_RANGE_CONSTRAINT; cleaning and retrying once…"
#                Cleanup-CAArtifacts -CACommonName $caName
#                Start-Sleep -Seconds 10
#            } else { throw }
#        }
#    } while ($true)
#} else {
#    Write-Host "Geen Enterprise Admins context → StandaloneRootCA (GPO-trust volgt)."
#    Install-AdcsCertificationAuthority `
#        -CAType StandaloneRootCA `
#        -CACommonName $caName `
#        -CryptoProviderName $ksp `
#        -KeyLength 2048 `
#        -HashAlgorithmName SHA256 `
#        -ValidityPeriod Years `
#        -ValidityPeriodUnits 5 `
#        -DatabaseDirectory $caDB `
#        -LogDirectory $caLog `
#        -Force
#}

# Web Enrollment (requires IIS role files; ADCS-Web-Enrollment gets installed by Ensure-ADCSDeploymentModule if missing)
#Install-AdcsWebEnrollment -Force

# -------------------------
# Publish / trust
# -------------------------
#Write-Host "--- Stap 4.5: Rootcert export + publicatie ---"
#$root = Get-ChildItem Cert:\LocalMachine\CA | Where-Object { $_.Subject -like "CN=$caName*" } | Select-Object -First 1
#if ($root) {
#    $cer = "C:\$($caName).cer"
#    Export-Certificate -Cert $root -FilePath $cer | Out-Null

#    # Publish to AD (harmless for standalone; useful for enterprise) 
#    try { certutil -dspublish -f $cer RootCA | Out-Null } catch { }
#}

# Optional GPO auto-enrollment (only if GroupPolicy module is present AND domain context works)
#Write-Host "--- Stap 4.6: (Optioneel) GPO auto-enrollment ---"
#$canGPO = $false
#try {
#    Import-Module GroupPolicy -ErrorAction Stop
#    # simple domain access check
#    $null = (Get-ADDomain -ErrorAction Stop)
#    $canGPO = $true
#} catch { $canGPO = $false }

#if ($canGPO) {
#    $gpoName = 'Enterprise CA Auto-Enrollment'
#    if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
#        $gpo = New-GPO -Name $gpoName
#        New-GPLink -Name $gpoName -Target ((Get-ADDomain).DistinguishedName) -Enforced:$false | Out-Null
#    }
#    # Enable AE: HKLM\Software\Policies\Microsoft\Cryptography\AutoEnrollment\AEPolicy = 7
#    Set-GPRegistryValue -Name $gpoName `
#        -Key 'HKLM\Software\Policies\Microsoft\Cryptography\AutoEnrollment' `
#        -ValueName 'AEPolicy' -Type DWord -Value 7
#    Write-Host "GPO auto-enrollment geactiveerd."
#} else {
#    Write-Host "GPO auto-enrollment overgeslagen (GroupPolicy/AD context niet beschikbaar)."
#}

#Write-Host "--- Stap 4.7: IIS/HTTP firewall (fallback) ---"
#try {
#    New-NetFirewallRule -DisplayName "HTTP 80 Inbound"  -Direction Inbound -Protocol TCP -LocalPort 80  -Action Allow -ErrorAction SilentlyContinue | Out-Null
#    New-NetFirewallRule -DisplayName "HTTPS 443 Inbound" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -ErrorAction SilentlyContinue | Out-Null
#} catch { }

#Write-Host "==> CA/Web Enrollment klaar."
