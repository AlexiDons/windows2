# Deployment Guide – Windows Server II (Deel 1)

**Auteur:** Alexi Dons
**Klasgroep:** 3B
**Datum:** 13-11-2025

---

## 1. Doel

Automatische uitrol van een Windows Server 2025 omgeving met:

* Active Directory domein
* DNS
* DHCP
* Certificate Services (CA + Web Enrollment)
* Tweede server (secundaire DNS + SQL basis)
* Client die automatisch in het domein zit

Alles via:

```bash
vagrant up
```

---

## 2. Architectuur

Intern netwerk: `192.168.25.0/24`

| VM      | OS                       | Rollen                       | IP            |
| ------- | ------------------------ | ---------------------------- | ------------- |
| server1 | Windows Server 2025 Core | DC, DNS, DHCP, CA, CertSrv   | 192.168.25.10 |
| server2 | Windows Server 2025 Core | Secundaire DNS, SQL (deel 2) | 192.168.25.20 |
| client  | Windows 10               | Domeinclient, RSAT, SSMS     | via DHCP      |

Domein: **WS2-25-alexi.hogent**

---

## 3. Vereisten op de host

**Software**

* VirtualBox 7.2.2
* Vagrant 2.4.9

**Hyper-V uit**

* Windows-onderdelen in- of uitschakelen
* Hyper-V, Virtual Machine Platform, Windows Hypervisor Platform uit
* Herstart

**Projectmap bevat**

* `Vagrantfile`
* `scripts\` met alle `.ps1`
* SQL ISO (voor SQL / deel 2)

---

## 4. Scripts en flow

Vagrant voert scripts uit in deze volgorde:

```text
Server1:
01_network.ps1
02_install_adds_features.ps1
03_promote_dc.ps1
04_configure_users_ou.ps1
05_configure_dhcp.ps1
06_configure_dns.ps1
07_post_dc_config.ps1

Server2:
08_configure_server2_networks.ps1
09_configure_server2_roles.ps1
10_update_dhcp_dns_option.ps1

Client:
11_configure_client.ps1
```

### 4.1 Korte uitleg per script

**01_network.ps1 (server1)**
Statisch IP 192.168.25.10.
DNS op de NIC.
Firewallregels voor WinRM en SSH.

**02_install_adds_features.ps1 (server1)**
Installeert AD DS en DNS.

**03_promote_dc.ps1 (server1)**
Maakt domein **WS2-25-alexi.hogent**.
Promoot server1 tot eerste DC.
Reboot na promotie.

**04_configure_users_ou.ps1 (server1)**
Wacht tot AD online is.
Maakt OUs: IT, HR, Students.
Maakt users: admin1, admin2, user1, user2.
Zet admin1 en admin2 in Domain Admins + Enterprise Admins.

**05_configure_dhcp.ps1 (server1)**
Wacht op AD + DHCP.
Autoriseert DHCP in AD.
Maakt scope in `192.168.25.0/24`.
Opties: 003 router, 006 DNS (server1 + server2), 015 domeinnaam.

**06_configure_dns.ps1 (server1)**
Forward zone `WS2-25-alexi.hogent`.
Reverse zone `25.168.192.in-addr.arpa`.
A + PTR voor server1 en server2.
Zone transfers richting server2.

**07_post_dc_config.ps1 (server1)**
Installeert AD CS (Enterprise Root CA) + Web Enrollment.
Configureert IIS voor `/CertSrv` (Windows Auth + Anonymous).
Publiceert CA + CRL in AD.
Maakt GPO voor auto-enrollment.
Firewallregel voor HTTP.
Health check op `/CertSrv`.

**08_configure_server2_networks.ps1 (server2)**
Statisch IP 192.168.25.20.
DNS naar server1.
Join server2 in het domein.

**09_configure_server2_roles.ps1 (server2)**
Installeert secundaire DNS.
Haalt zones binnen via zone transfer.
Bereidt SQL install (deel 2).

**10_update_dhcp_dns_option.ps1 (server2)**
Past DHCP op server1 aan.
Zorgt dat optie 006 twee DNS-servers doorgeeft: 192.168.25.10 en .20.

**11_configure_client.ps1 (client)**
Verkeerde NIC uit (NAT/internet).
Client krijgt IP via DHCP.
Join in domein.
Installeert RSAT + SSMS.
Haalt GPO’s en CA-certificaat binnen.

---

## 5. Uitrol

In de projectmap:

```bash
vagrant up
```

Vagrant:

* bouwt de drie VM’s
* voert alle scripts uit
* herstart waar nodig

Klaar als de prompt terugkomt en alle VM’s in VirtualBox draaien.

**Accounts in AD**

| User   | Wachtwoord           | Rol                             |
| ------ | -------------------- | ------------------------------- |
| admin1 | P@ssw0rdVoorHerstel! | Domain Admin + Enterprise Admin |
| admin2 | P@ssw0rdVoorHerstel! | Domain Admin + Enterprise Admin |
| user1  | P@ssw0rdVoorHerstel! | Domain User                     |
| user2  | P@ssw0rdVoorHerstel! | Domain User                     |
| sa     | S@feSqlP4ss!         | SQL `sa`                        |

Ik log op de client in als:

```text
WS2-25-alexi\admin1
```

---

## 6. Validatie en demo

Alle checks die ik in de video toon.

### 6.1 DC / Active Directory

**Login bewijs**

* Inloggen als `ALEXI\admin1` op server
* Inloggen als `WS2-25-alexi\admin1` op client

**AD Users and Computers**

```powershell
dsa.msc
```

Toon:

* OUs: IT, HR, Students
* Users: admin1, admin2, user1, user2
* admin1 en admin2 in Domain Admins + Enterprise Admins

**CLI check**

```powershell
Get-ADUser admin1 -Properties memberOf
```

---

### 6.2 DNS (server1, server2, client)

**DNS Manager**

```powershell
dnsmgmt.msc
```

Toon:

* Forward zone `WS2-25-alexi.hogent` op beide servers
* Reverse zone `25.168.192.in-addr.arpa` op beide servers

**Records / zones**

```powershell
Get-DnsServerZone
Get-DnsServerResourceRecord -ZoneName "WS2-25-alexi.hogent"
Get-DnsServerResourceRecord -ZoneName "25.168.192.in-addr.arpa"
```

**Replicatie**

```powershell
repadmin /replsummary
```

**nslookup**

```powershell
nslookup server1
nslookup server2
nslookup
server 192.168.25.20
server1
exit
```

**DNS sync demo**

* Op server1: nieuw A-record `sync-test` → 192.168.25.99
* Op server2: zone refresh
* `sync-test` verschijnt mee

---

### 6.3 DHCP

**DHCP Manager**

```powershell
dhcpmgmt.msc
```

Toon:

* Scope actief
* Juiste range
* Optie 006: 192.168.25.10 en .20
* Lease van client

**CLI**

```powershell
Get-DhcpServerv4Scope
Get-DhcpServerv4OptionValue -ScopeId 192.168.25.0
Get-DhcpServerv4Lease -ScopeId 192.168.25.0
```

**Client IP-config**

```powershell
ipconfig /all
```

Toon:

* IP in 192.168.25.x
* DHCP server = 192.168.25.10
* DNS = 192.168.25.10 en .20

**Renew**

```powershell
ipconfig /release
ipconfig /renew
```

---

### 6.4 CA en auto-enrollment

**CA console**

```powershell
certsrv.msc
```

Toon:

* CA = WS2-CA
* Status Running

**CRL en publish**

```powershell
certutil -crl
certutil -dspublish -f
```

**Root CA op client**

```powershell
certmgr.msc
```

Toon:

* WS2-CA onder *Trusted Root Certification Authorities*

**Policies forceren**

```powershell
gpupdate /force
certutil -pulse
```

**CRL test**

```powershell
certutil -url http://server1/CertEnroll/WS2-CA.crl
```

---

### 6.5 Web Enrollment

Op client in browser:

```text
http://server1/CertSrv
```

Toon:

* CertSrv pagina
* Geen 403 of 404

---

### 6.6 Client – domein en netwerk

Op de client als `WS2-25-alexi\admin1`:

```powershell
ipconfig /all
nltest /dsgetdc:WS2-25-alexi.hogent
nslookup server1
nslookup server2
ping server1
ping server2
```

---

### 6.7 SQL / SSMS (basis)

Op de client:

```powershell
ssms
```

Connect via Windows Authentication naar SQL op server2.

Test:

```sql
CREATE DATABASE DemoDB;
GO
```

Toon dat `DemoDB` zichtbaar is.

---

### 6.8 Firewall

Op server1 en server2:

```powershell
Get-NetFirewallProfile
Get-NetFirewallRule | Where-Object { $_.Enabled -eq "True" }
```

Toon dat:

* Domain-profiel actief is
* DNS, DHCP, AD DS, WinRM, HTTP rules actief zijn

---

## 7. Status en analyse

* Alle vereisten voor **Deel 1** zijn geautomatiseerd

* `vagrant up` bouwt:

  * DC met DNS, DHCP, CA, CertSrv
  * Tweede server met secundaire DNS en SQL basis
  * Client in domein met RSAT en SSMS

* Scripts zijn idempotent

* Wacht-loops en checks lossen timingproblemen op

* Firewall blijft aan, enkel nodige poorten open

---

## 8. Reflectie

**Geleerd**

* Automatisatie moet herhaalbaar zijn
* Idempotentie en timing zijn cruciaal
* AD, DNS, DHCP, CA, GPO hangen hard samen

**In de toekomst**

* Nog meer kleine teststappen
* Nog meer comments in de scripts

**Tijdverlies**

* AD CS Web Enrollment (403/404)
* Timing van AD, DHCP, CA, WinRM

Oplossing: betere IIS-config, Anonymous erbij, health checks, wacht-loops.
