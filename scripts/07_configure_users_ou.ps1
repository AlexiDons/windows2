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
    } catch {
        Write-Host "Poging $attempt/$maxAttempts - wacht 10 seconden..."
        Start-Sleep -Seconds 10
    }
}

if ($attempt -eq $maxAttempts) {
    Write-Error "Timeout: AD niet operationeel"
    exit 1
}

# Extra wachttijd om AD volledig te laten stabiliseren na de reboot.
Write-Host "AD is online. Wacht 30 seconden extra voor stabilisatie..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

Write-Host "--- Stap 7: OUs en Users configureren... ---" -ForegroundColor Green

$Domain = "WS2-25-alexi.hogent"
$BaseDN = "DC=WS2-25-alexi,DC=hogent"
$defaultPwd = ConvertTo-SecureString "P@ssw0rdVoorHerstel!" -AsPlainText -Force


Import-Module ActiveDirectory
Add-ADGroupMember -Identity "Domain Admins" -Members "vagrant"  -ErrorAction SilentlyContinue
Add-ADGroupMember -Identity "DNSAdmins"     -Members "vagrant"  -ErrorAction SilentlyContinue

# OUs (minstens 3)
$OUs = @('IT', 'HR', 'Students') 
foreach ($ou in $OUs) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -SearchBase $BaseDN -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $ou -Path $BaseDN -ProtectedFromAccidentalDeletion $false
        Write-Host "OU '$ou' aangemaakt"
    }
}

# Users (2 admins, 2 users)
$users = @(
    @{ Sam='admin1'; Given='Admin'; Surname='One'; OU='IT'; IsAdmin=$true },
    @{ Sam='admin2'; Given='Admin'; Surname='Two'; OU='IT'; IsAdmin=$true },
    @{ Sam='user1'; Given='User'; Surname='One'; OU='Students'; IsAdmin=$false },
    @{ Sam='user2'; Given='User'; Surname='Two'; OU='Students'; IsAdmin=$false }
)

foreach ($u in $users) {
    $userPath = "OU=$($u.OU),$BaseDN"
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue)) {
        New-ADUser -Name "$($u.Given) $($u.Surname)" `
            -GivenName $u.Given -Surname $u.Surname `
            -SamAccountName $u.Sam `
            -UserPrincipalName "$($u.Sam)@$Domain" `
            -Path $userPath `
            -AccountPassword $defaultPwd `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -ChangePasswordAtLogon $false
        Write-Host "User $($u.Sam) aangemaakt"
        
        if ($u.IsAdmin) {
            Add-ADGroupMember -Identity "Domain Admins" -Members $u.Sam
            Add-ADGroupMember -Identity "Enterprise Admins" -Members $u.Sam
            Write-Host "$($u.Sam) toegevoegd aan Domain Admins en Enterprise Admins"
        }
    }
}

Write-Host "Configuratie van OUs en Users is voltooid."
Write-Host "--- VOLLEDIGE PROVISIONING SERVER1 VOLTOOID ---" -ForegroundColor Magenta