# Veröffentlichung und Betrieb

Ziel ist `https://kleinunternehmerzentrale.de` auf einem einzelnen Linux-Server
mit amd64-Prozessor. Kamal betreibt den Rails-Container und den HTTPS-Proxy.
SQLite-Datenbanken und Dateien liegen dauerhaft im Docker-Volume
`kleinunternehmerzentrale_storage`; neue Images ersetzen dieses Volume nicht.

## Einmalige Einrichtung

1. Server-IP und SSH-Benutzer festlegen. Der Benutzer benötigt Docker-Zugriff;
   bei einer frischen Installation benötigt Kamal außerdem Rechte zum Einrichten
   von Docker. Die bestehende Vorgabe ist `root`. Einen eigenen SSH-Schlüssel
   ausschließlich für GitHub Actions erzeugen und dessen öffentlichen Teil beim
   Serverbenutzer in `authorized_keys` hinterlegen.
2. DNS-A-Record für `kleinunternehmerzentrale.de` auf die IPv4-Adresse setzen.
   Einen AAAA-Record nur setzen, wenn IPv6 ebenfalls korrekt eingerichtet ist.
   Ports 80 und 443 müssen öffentlich erreichbar sein, SSH für den Runner ebenfalls.
   `www` ist derzeit keine konfigurierte zusätzliche Domain.
3. Im GitHub-Repository unter **Settings → Environments → production** die
   folgenden Variablen und Secrets einrichten. Secrets niemals in Chat, Git oder
   Workflow-Protokolle kopieren.

| Art | Name | Inhalt |
| --- | --- | --- |
| Variable | `DEPLOY_SERVER_IP` | Server-IP oder SSH-Hostname |
| Variable | `DEPLOY_SSH_USER` | SSH-Benutzer, sonst `root` |
| Variable | `SMTP_ADDRESS` | Mailserver, sonst `mail.your-server.de` |
| Variable | `SMTP_PORT` | STARTTLS-Port, sonst `587` |
| Secret | `DEPLOY_SSH_PRIVATE_KEY` | Eigener privater Deployment-Schlüssel |
| Secret | `DEPLOY_SSH_KNOWN_HOSTS` | Verifizierter SSH-Hostschlüssel im known_hosts-Format |
| Secret | `RAILS_MASTER_KEY` | Passender Schlüssel zu `config/credentials.yml.enc` |
| Secret | `SMTP_USERNAME` | Benutzername des Versandpostfachs |
| Secret | `SMTP_PASSWORD` | Passwort des Versandpostfachs |

Den Server-Hostschlüssel anhand der Hoster-Konsole oder einer bereits verifizierten
SSH-Verbindung prüfen. `ssh-keyscan` allein bestätigt nicht die Identität des Servers.
Der Workflow überprüft die Identität strikt, statt unbekannte Schlüssel zu akzeptieren.
Bei Übernahme der lokalen Daten den bisherigen Rails-Schlüssel weiterverwenden.

4. Änderungen auf `main` pushen. Beim ersten Push auf einen noch nicht eingerichteten
   Server kann der abschließende Deploy-Schritt scheitern; die Prüfungen laufen trotzdem.
   Danach unter **Actions → CI → Run workflow** auf `main` die Option
   **Erstinstallation mit Kamal setup durchführen** aktivieren. Dadurch laufen zuerst
   alle Prüfungen und anschließend `bin/kamal setup`.
5. Domain, Anmeldung, Bestätigungs- und Passwort-E-Mail prüfen. Das Deployment
   prüft automatisch zusätzlich `https://kleinunternehmerzentrale.de/up`.

## Jeder weitere Push

Ein Push auf `main` startet Rails-, JavaScript- und Systemtests, Stil- und
Sicherheitsprüfungen sowie den Bau und Start des Produktionsimages mit einer leeren
Testdatenbank. Nur wenn sämtliche Jobs erfolgreich sind, startet `bin/kamal deploy`.
Pull Requests deployen nicht. Gleichzeitige Läufe desselben Branches werden
serialisiert; ein laufendes Deployment wird nicht durch einen neuen Push abgebrochen.

Kamal baut den eingecheckten Git-Stand. Das Image wird von einer lokalen Registry
auf dem GitHub-Runner über einen SSH-Tunnel übertragen. Ein dauerhaftes Registry-Token
oder eine zusätzliche öffentliche Container-Registry ist nicht erforderlich.
Kamal startet den neuen Container, wartet auf dessen Healthcheck und schaltet dann
die Anfragen um. Datenbankschemata werden beim Containerstart mit `db:prepare`
eingerichtet bzw. migriert.

## Lokal dieselben Prüfungen ausführen

`bin/ci` enthält die Anwendungsprüfungen und den Produktionsimage-Check.
Chrome, Node, Ruby und ein laufender Docker-Dienst sind dafür erforderlich.
Den Produktionscheck separat starten:

```sh
bash bin/check-production-image
```

Er verwendet ein eigenes temporäres Docker-Volume und entfernt Testcontainer und
Volume nach dem Lauf. Lokale Buchhaltungsdaten werden dabei nicht eingebunden.
Docker baut lokal für die Hostarchitektur; GitHub und Kamal bauen für amd64.

## Daten übernehmen und sichern

Die Veröffentlichung überträgt keine lokalen Buchhaltungsdaten. Der ZIP-Export ist
ein persönlicher Datenexport, kein automatischer Wiederherstellungsimport.
Für eine vollständige Übernahme einschließlich Konto und Verknüpfungen ist eine
konsistente Kopie der lokalen SQLite-Hauptdatenbank nötig, zum Beispiel mit der
SQLite-Funktion `.backup`. Eine laufende WAL-Datenbank nicht nur mit `cp` kopieren.
Die Kopie wird kontrolliert als `production.sqlite3` ins Storage-Volume übernommen,
während die App angehalten ist. Vor Überschreiben einer vorhandenen Serverdatenbank
diese separat sichern. Queue-, Cache- und Cable-Datenbanken bleiben serverseitig.

Der tägliche Job sichert die Hauptdatenbank um 03:00 Uhr nach `storage/backups`
und hält sieben Tagesstände vor. Diese Kopien liegen auf demselben Server.
Zusätzlich externe bzw. Hoster-Sicherungen einrichten und eine Wiederherstellung
testen. Vor Datenmigrationen eine aktuelle Sicherung erstellen.

Für Administration lokal dieselben Umgebungsvariablen wie im Workflow setzen;
zusätzlich `DEPLOY_SSH_KEY_PATH` auf den lokalen privaten Schlüssel zeigen lassen.
Danach stehen `bin/kamal logs`, `bin/kamal console` und `bin/kamal app details`
zur Verfügung. Keine Secret-Ausgaben aus `kamal config` veröffentlichen.
Ein Code-Rollback mit `bin/kamal rollback COMMIT_SHA` setzt keine Datenmigration
zurück; deshalb Schemaänderungen und Sicherungen gemeinsam planen.

## Vor der öffentlichen Freigabe

Der technische Rollout ersetzt die Prüfung der Betreiberangaben, des tatsächlichen
Hosting-/Mailvertrags und der Datenschutzerklärung nicht. Diese Angaben müssen zum
gewählten Betrieb passen. Auch E-Mail-Zustellung (SPF/DKIM/DMARC beim Mailanbieter),
externe Sicherungen und der Zugang zum Server müssen eingerichtet sein.
