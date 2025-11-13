# Deployment Guide – Windows Server II (Deel 1)

**Auteur:** Alexi Dons
**Klasgroep:** 3B
**Datum:** 13-11-2025
**Project:** Windows Server II – Automatisatie basisdiensten

---

## 1. Doel en Overzicht

Deze handleiding beschrijft hoe een volledige Windows Server 2025 omgeving automatisch wordt uitgerold met **één** commando:

```bash
vagrant up
```

Doel:

* Een volledig werkend **Active Directory domein**
* Met **DNS**, **DHCP**, **Certificate Services (CA + Web Enrollment)**
* Een **tweede server** met extra rollen
* Een **client** die automatisch in het domein zit
* Alles geconfigureerd via **PowerShell-scripts** en **Vagrant**

De README dient ook als gids voor de demo en de video.
Elke stap die ik toon in de video staat hier met het juiste commando.

---

## 2. Architectuur van de omgeving

De omgeving draait op een intern netwerk `192.168.25.0/24`.

| VM      | OS                       | Rollen                                     | IP            |
| ------- | ------------------------ | ------------------------------------------ | ------------- |
| server1 | Windows Server 2025 Core | Domain Controller, DNS, DHCP, CA, CertSrv  | 192.168.25.10 |
| server2 | Windows Server 2025 Core | Secundaire DNS, extra server (voor deel 2) | 192.168.25.20 |
| client  | Windows 10               | Domeinclient, RSAT, SSMS                   | via DHCP      |

Domein: **WS2-25-alexi.hogent**

Alles wordt automatisch opgebouwd via:

* `Vagrantfile`
* PowerShell scripts in de map `scripts/`

---

## 3. Vereisten op de host

Voor je `vagrant up` draait moet dit in orde zijn.

### 3.1 Software

1. **VirtualBox 7.2.2**
2. **Vagrant 2.4.9**

### 3.2 Hyper-V uit

Op Windows:

* Ga naar *Windows-onderdelen in- of uitschakelen*
* Alles van **Hyper-V**, **Virtual Machine Platform** en **Windows Hypervisor Platform** uitschakelen
* Herstart je pc

### 3.3 Projectbestanden

In de projectmap moet minstens staan:

* `Vagrantfile`
* `scripts\` map met alle `.ps1` scripts
* SQL ISO in dezelfde map als de Vagrantfile

---

## 4. Scripts en provisioning flow

Vagrant voert de scripts automatisch uit in deze volgorde:

```text
Server1:
01_network.ps1
02_install_adds_features.ps1
03_promote_dc.ps1
04_configure_users_ou.ps1
05_configure_dhcp.ps1
06_configure_dns.ps1
07_post_dc_config.ps1
10_configure_client.ps1
```

```text
Server2:
08_configure_server2_networks.ps1
09_configure_server2_roles.ps1
10_update_dhcp_dns_option
```

```text
Client:
11_configure_client.ps1
```

### 4.1 Korte beschrijving per script

#### 01_network.ps1 (server1)

* Stelt het juiste IP in op server1
* Zorgt dat de host-only adapter goed staat
* Maakt firewallregels voor WinRM en SSH
* Toont een duidelijke “network config completed” output

#### 02_install_adds_features.ps1 (server1)

* Installeert AD Domain Services
* Installeert DNS
* Bereidt server1 voor op promotie tot DC

#### 03_promote_dc.ps1 (server1)

* Promoot server1 tot eerste Domain Controller
* Maakt het domein **WS2-25-alexi.hogent**
* Gebruikt unattended promotie
* Triggert een reboot

#### 07_configure_users_ou.ps1 (server1)

* Wacht tot AD volledig online is (ADWS checks + sleeps)
* Maakt OUs:

  * IT
  * HR
  * Students
* Maakt users:

  * admin1, admin2, user1, user2
* Voegt admin1 en admin2 toe aan:

  * Domain Admins
  * Enterprise Admins

#### 05_configure_dhcp.ps1 (server1)

* Wacht op AD en DHCP service
* Autoriseert de DHCP server in AD
* Maakt scope in `192.168.25.0/24`
* Stelt DHCP options in, waaronder:

  * **003 Router**
  * **006 DNS Servers** → 192.168.25.10 en 192.168.25.20
  * **015 DNS Domain Name** → WS2-25-alexi.hogent

#### 06_configure_dns.ps1 (server1)

* Maakt forward lookup zone: `WS2-25-alexi.hogent`
* Maakt reverse zone: `25.168.192.in-addr.arpa`
* Voegt A-records voor server1 en server2 toe
* Voegt PTR-records toe
* Activeert zone transfers en replicatie (voor server2)

#### 04_post_dc_config.ps1 (server1)

* Wacht op AD
* Installeert **Active Directory Certificate Services** (Enterprise Root CA)
* Installeert **ADCS-Web-Enrollment**
* Configureert IIS:

  * `Default Web Site/CertSrv`
  * Windows Authentication = **Enabled**
  * Anonymous Authentication = **Enabled**
* Publiceert CA-certificaat en CRL in AD
* Maakt een GPO voor **certificaat auto-enrollment**
* Activeert firewall rule voor HTTP (poort 80)
* Doet een health check voor `/CertSrv`

#### 10_configure_client.ps1 (client)

* Schakelt de verkeerde NIC (NAT / Telenet) uit
* Laat de client via DHCP een IP krijgen in `192.168.25.x`
* Joint de client in het domein
* Installeert RSAT tools
* Zorgt dat de client de CA en GPO’s binnenkrijgt

---

## 5. Uitrolprocedure

### 5.1 Start provisioning

In een terminal in de projectmap:

```bash
vagrant up
```

Vagrant:

* Downloadt de base images (eerste keer duurt lang)
* Maakt server1, server2 en client
* Voert alle scripts uit
* Herstart servers waar nodig

De uitrol is klaar wanneer de prompt terugkomt en de VMs in VirtualBox draaien.

### 5.2 Inloggegevens

Accounts in AD:

| Gebruiker | Wachtwoord           | Rol                             |
| --------- | -------------------- | ------------------------------- |
| admin1    | P@ssw0rdVoorHerstel! | Domain Admin + Enterprise Admin |
| admin2    | P@ssw0rdVoorHerstel! | Domain Admin + Enterprise Admin |
| user1     | P@ssw0rdVoorHerstel! | Domain User                     |
| user2     | P@ssw0rdVoorHerstel! | Domain User                     |

Op de client log ik meestal in als:

```text
WS2-25-alexi\admin1
```

---

### 6. Validatie en demo (commando’s die ik toon)

**DC check:**

Je kan inloggen in het domein en bewijs van de 2 servers hun schermen
ALEXI\admin1
WS2-25-alexi\admin1

---

### 6.2 Server1 – DNS testen

```powershell
nslookup server1
nslookup server2
nslookup 192.168.25.10
nslookup 192.168.25.20
```

Verwachting:

* Namen en IP’s komen uit **eigen DNS**
* Geen externe resolvers

---

### 6.3 Server1 – DHCP testen

In **DHCP Manager**:

* Scope actief
* IP-reeks is correct
* Lease voor client bestaat
* Scope options → 006 DNS Servers =

  * 192.168.25.10
  * 192.168.25.20

CLI check:

```powershell
Get-DhcpServerv4Scope
Get-DhcpServerv4OptionValue -ScopeId 192.168.25.0
```

---

### 6.4 Server1 – OUs en users

GUI:

```powershell
dsa.msc
```

Check:

* OU IT
* OU HR
* OU Students
* Gebruikers admin1, admin2, user1, user2 aanwezig
* admin1 en admin2 zitten in Domain Admins en Enterprise Admins

CLI:

```powershell
Get-ADUser admin1 -Properties memberOf
```

---

### 6.5 Server1 – Certificate Authority

Open CA console:

```powershell
certsrv.msc
```

Check:

* CA = WS2-CA
* Status = Running

CRL genereren:

```powershell
certutil -crl
```

Publicatie in AD:

```powershell
certutil -dspublish -f
```

---

### 6.6 Web Enrollment (IIS / CertSrv)

Test vanaf de client in browser:

```text
http://server1/CertSrv
```

---

### 6.7 Client – netwerk en domein

Op de client (als admin1):

**IP en DNS check:**

```powershell
ipconfig /all
```

Verwachting:

* IPv4 in 192.168.25.x
* DHCP server = 192.168.25.10
* DNS servers = 192.168.25.10 en 192.168.25.20
* Geen externe Telenet DNS meer

**DC discovery:**

```powershell
nltest /dsgetdc:WS2-25-alexi.hogent
```

**DNS vanaf client:**

```powershell
nslookup server1
nslookup server2
```

**Ping:**

```powershell
ping server1
ping server2
```

---

### 6.8 Client – Auto-enrollment en CA trust

Open de user certificate store:

```powershell
certmgr.msc
```

Check:

* Onder **Trusted Root Certification Authorities → Certificates** staat **WS2-CA**

Policies forceren:

```powershell
gpupdate /force
certutil -pulse
```

CRL test:

```powershell
certutil -url http://server1/CertEnroll/WS2-CA.crl
```

Verwachting: Status OK

---

## 7. Status en technische analyse

### 7.1 Huidige status

* Alle vereisten voor **Deel 1** zijn geautomatiseerd

---

## 8. Reflectie

### 8.1 Wat heb ik hier vooral uit geleerd

* Een script dat maar één keer werkt is waardeloos
* Je moet altijd denken aan:

  * Idempotentie
  * Timing
  * Dependencies tussen services
* AD, DNS, DHCP, CA en GPO’s zijn stevig aan elkaar gelinkt
* Kleine fouten in DNS of firewall breken snel alles

### 8.2 Wat zou ik anders doen in de toekomst

* Meer testen door kleinere stappen te nemen
* Nog meer onderzoek doen via documentatie

### 8.3 Waar heb ik veel tijd op verloren

* AD CS Web Enrollment:
  * Veel trial and error om 403/404 op te lossen
* Timing problemen:
  * Services die nog niet klaar zijn na reboot
  * Vooral CA en DHCP maar ook vagrant en WINRM
* Dit heeft geleid tot:
  * Betere wacht-loops
  * Betere check op afhankelijkheden

---
