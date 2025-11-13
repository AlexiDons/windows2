# Opdracht Windows Server II - Deel 1: Automatisatie Basisdiensten

- **Naam:** `[JOUW NAAM HIER]`
- **Klasgroep:** `[JOUW KLASGROEP HIER]`
- **Datum:** 12 november 2025

---

## Deel 1: Deployment Guide

Deze handleiding beschrijft de stappen die nodig zijn om de volledige Windows Server omgeving voor Deel 1 van de opdracht automatisch uit te rollen. De setup is ontworpen om "dummy-proof" te zijn voor een student uit het eerste jaar Toegepaste Informatica.

### 1.1 Vereisten

Voordat u begint, zorg ervoor dat de volgende software op uw systeem is geïnstalleerd:

1.  **VirtualBox:** Versie 7.2.2 of recenter.
2.  **Vagrant:** Versie 2.4.0 of recenter.
3.  **SQL Server 2022 ISO:**
    - Download het ISO-bestand voor Microsoft SQL Server 2022 Standard.
    - De bestandsnaam moet exact `enu_sql_server_2022_standard_edition_x64_dvd_43079f69.iso` zijn.
    - Plaats dit ISO-bestand in dezelfde map als de `Vagrantfile`. Zonder dit bestand zal de provisionering van `server2` mislukken.

### 1.2 Uitrol van de Omgeving

De volledige omgeving, inclusief drie virtuele machines (`server1`, `server2`, `client`) en alle configuraties, kan met één commando worden uitgerold.

1.  Open een terminal of command prompt.
2.  Navigeer naar de map waar de `Vagrantfile` en de `scripts` map zich bevinden.
3.  Voer het volgende commando uit:

    ```bash
    vagrant up
    ```

4.  **Geduld:** Het proces zal aanzienlijke tijd in beslag nemen, vooral de eerste keer. Vagrant zal de basis-VM's downloaden (meerdere gigabytes), de VM's importeren, opstarten en vervolgens de PowerShell-provisioningscripts uitvoeren. Er zullen meerdere automatische reboots plaatsvinden zoals geconfigureerd in de `Vagrantfile`.
5.  Na voltooiing draait de volledige omgeving en zijn alle services geconfigureerd.

### 1.3 Overzicht Gebruikers en Wachtwoorden

De volgende gebruikers worden aangemaakt tijdens de provisionering.

| Gebruiker | Rol | Standaard Wachtwoord |
| :--- | :--- | :--- |
| `admin1` | Domain Admin | `P@ssw0rdVoorHerstel!` |
| `admin2` | Domain Admin | `P@ssw0rdVoorHerstel!` |
| `user1` | Domain User | `P@ssw0rdVoorHerstel!` |
| `user2` | Domain User | `P@ssw0rdVoorHerstel!` |
| `vagrant` | Lokale admin (Vagrant) | `vagrant` |
| `sa` | SQL System Admin | `S@feSqlP4ss!` |

---

## Deel 2: Project Status & Reflectie

### 2.1 Status: Afgewerkt

Alle vereisten voor Deel 1 van de opdracht zijn geïmplementeerd en geautomatiseerd.

-   [x] **VM Architectuur:** 3 VM's (`server1`, `server2`, `client`) worden aangemaakt via Vagrant.
-   [x] **Netwerkconfiguratie:**
    -   `server1` en `server2` hebben een statisch IP-adres.
    -   `client` ontvangt zijn IP-adres via de DHCP-server.
-   [x] **Active Directory:**
    -   `server1` is gepromoveerd tot Domain Controller voor het domein `WS2-25-alexi.hogent`.
    -   Forest en Domain Functional Level zijn `Windows Server 2025`.
-   [x] **DNS:**
    -   `server1` is de primaire, AD-geïntegreerde DNS-server.
    -   `server2` is de secundaire DNS-server.
    -   Forward en Reverse lookup zones zijn geconfigureerd met zone transfers.
    -   Client DNS-registratie is uitgeschakeld zoals vereist.
-   [x] **DHCP:**
    -   `server1` is de DHCP-server.
    -   Een scope (`192.168.25.50` - `192.168.25.150`) is geconfigureerd en geautoriseerd in AD.
-   [x] **Certificate Authority (CA):**
    -   Een Enterprise Root CA is geïnstalleerd op `server1`.
    -   Web Enrollment (`/CertSrv`) is functioneel.
    -   Een GPO is geconfigureerd voor automatische certificaat-uitrol.
-   [x] **Users en OU's:**
    -   3 OU's (`IT`, `HR`, `Students`) zijn aangemaakt.
    -   4 gebruikers (2 admins, 2 users) zijn aangemaakt en in de juiste OU's geplaatst.
-   [x] **Microsoft SQL Server:**
    -   SQL Server 2022 wordt automatisch geïnstalleerd op `server2` vanaf de ISO.
    -   Mixed-mode authenticatie is ingeschakeld en de firewall is geconfigureerd.
-   [x] **Client Tools:**
    -   RSAT-tools en SQL Server Management Studio (SSMS) worden automatisch geïnstalleerd op de `client` VM via Chocolatey.

### 2.2 Status: Niet Afgewerkt

-   Alle onderdelen van **Deel 1** zijn voltooid.
-   **Deel 2** (SharePoint + OneDrive) is nog niet gestart, zoals de opdracht voorschrijft.

### 2.3 Problemen en Oplossingen

Tijdens de ontwikkeling kwamen enkele specifieke problemen naar voren:

1.  **Probleem:** De `client` VM kreeg wel een IP van de DHCP-server, maar de DNS-instelling werd handmatig overschreven in het script, wat de DHCP-demonstratie onvolledig maakte.
    -   **Oplossing:** De regel `Set-DnsClientServerAddress` is uit het `10_configure_client.ps1` script verwijderd. Hierdoor ontvangt de client nu zijn volledige netwerkconfiguratie (inclusief DNS) van de DHCP-server.

2.  **Probleem:** Bij het configureren van de Certificate Authority faalde het script initieel omdat de `Get-CertificationAuthority` cmdlet niet herkend werd en er "duplicate entry" fouten optraden bij het herhaaldelijk uitvoeren.
    -   **Oplossing:** Het `04_post_dc_config.ps1` script is grondig herschreven. De afhankelijkheid van de `ADCSAdministration` module is weggenomen door `certutil.exe` te gebruiken. De logica voor het configureren van IIS-authenticatie is robuuster gemaakt om "duplicate entry" fouten te voorkomen, wat de algehele betrouwbaarheid van het script heeft verhoogd.

### 3.1 Wat heb je geleerd?

*(Let op: Pas deze sectie aan met uw eigen persoonlijke reflecties.)*

Ik heb geleerd hoe cruciaal de juiste volgorde van operaties is bij het automatiseren van een complexe serveromgeving. De afhankelijkheden tussen Active Directory, DNS en DHCP vereisen dat scripts in een specifieke, weldoordachte volgorde worden uitgevoerd, inclusief reboots op de juiste momenten. Daarnaast heb ik het belang van **idempotentie** in de praktijk ervaren; scripts moeten zo geschreven zijn dat ze herhaaldelijk kunnen worden uitgevoerd zonder fouten te veroorzaken, wat het debuggen aanzienlijk vereenvoudigt.

### 3.2 Wat zou je anders doen?

*(Let op: Pas deze sectie aan met uw eigen persoonlijke reflecties.)*

In de toekomst zou ik nog meer gebruikmaken van parameters en configuratievariabelen bovenaan de scripts of in een apart configuratiebestand. Hoewel de domeinnaam nu consistent is, zou het centraliseren van dergelijke variabelen het nog makkelijker maken om de setup voor een ander domein aan te passen. Ook zou ik vroeger in het proces beginnen met het testen van de communicatie tussen de verschillende VM's om firewall- en netwerkproblemen sneller te identificeren.

### 3.3 Wat heeft veel tijd gekost?

*(Let op: Pas deze sectie aan met uw eigen persoonlijke reflecties.)*

Het debuggen van de `04_post_dc_config.ps1` script voor de Certificate Authority en IIS heeft de meeste tijd gekost. De interactie met IIS, het correct instellen van permissies en het garanderen dat de web enrollment-pagina correct werkte, was complex. Het doorgronden van de exacte PowerShell-cmdlets en hun parameters voor de GPO-configuratie en de AD CS-publicatie in Active Directory was een tijdrovende maar zeer leerzame uitdaging.