# Variabelen (Aangepast naar jouw opdracht)
$DomainName       = "WS2-25-alexi.hogent"
$NetbiosName      = "ALEXI"
$SafeModePassword = ConvertTo-SecureString "P@ssw0rdVoorHerstel!" -AsPlainText -Force

Write-Host "Start DC promotie..."

Import-Module ADDSDeployment

# BELANGRIJK: NoRebootOnCompletion = $true
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainMode "Win2025" `
    -DomainNetbiosName $NetbiosName `
    -ForestMode "Win2025" `
    -InstallDns:$true `
    -SafeModeAdministratorPassword $SafeModePassword `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -NoRebootOnCompletion:$true `
    -Force:$true

Write-Host "DC promotie voltooid. Wacht op reboot..."