# Kleinunternehmerzentrale

Eine deutschsprachige Anwendung für Rechnungen, Buchhaltung und die Vorbereitung
der Einnahmenüberschussrechnung (EÜR). Ziel ist ein kostenloser, spendenfinanzierter
Betrieb ohne Werbung und Tracking. Die Anwendung richtet sich an Kleinunternehmer;
sie ersetzt keine steuerliche Prüfung des eigenen Geschäftsfalls.

## Funktionen

- Rechnungen mit Entwürfen, Vorschau, Druck/PDF, XRechnung sowie Storno/Korrektur.
- Angebote, Aufträge, Anzahlungs-, Abschlags- und Schlussrechnungen.
- Kunden, Stundensätze und deutsche Datumseingabe; Entwürfe geräteübergreifend
  fortsetzen, wenn sie zum selben Benutzerkonto gehören.
- Erfassung von Zahlungen, Ausgaben, Einlagen, Entnahmen und Anlagegütern.
- Jahresübersichten und EÜR-Vorbereitung für die geprüften Jahre 2025 und 2026.
- Vorschau für die Übernahme bisheriger Buchhaltung per Eingabe, CSV oder
  textbasiertem sevdesk-EÜR-PDF.
- E-Rechnungsviewer ausschließlich lokal im Browser, ohne Datei-Upload.
- Gastbereiche, optionale Benutzerkonten, persönlicher Datenexport und Löschung.

Die Anwendung übermittelt keine Daten direkt an ELSTER. Zahlungserfassung und
Datenexport ersetzen keine Belegaufbewahrung. Fachlicher Umfang und Grenzen stehen
in [docs/buchhaltung-umfang.md](docs/buchhaltung-umfang.md) und in der Anwendungshilfe.

## Entwicklung

Rails 8.1, Ruby gemäß `.tool-versions`, SQLite, ERB, Hotwire/Stimulus und Importmap.
Ein zusätzlicher Frontend-Build ist nicht nötig. Node gemäß `.nvmrc` wird für
JavaScript-Tests verwendet. Außerdem werden Chrome, libvips und Poppler benötigt.
Unter macOS: `brew install vips poppler`.

```sh
bundle install
bin/rails db:prepare
bin/dev
```

## Qualität prüfen

```sh
PARALLEL_WORKERS=1 bin/rails test
node --test test/javascript/*.mjs
bin/rails test:system
bin/rubocop
git diff --check
```

Rails-Testläufe nicht gleichzeitig gegen dieselbe SQLite-Testdatenbank starten.
Systemtests starten ihren eigenen Server und verwenden Testdaten. Fehlerbilder
liegen unter `tmp/screenshots`. Der vollständige Ablauf einschließlich
Sicherheitsprüfungen und Docker-Produktionsstart ist `bin/ci`; dafür muss Docker laufen.
Nur den Produktionscontainer prüfen: `bash bin/check-production-image`.

## Veröffentlichung

Ziel ist `https://kleinunternehmerzentrale.de` auf einem einzelnen Linux-Server.
Nach Einrichtung deployt ein Push auf `main` automatisch mit Kamal, sobald alle
GitHub-Actions-Prüfungen bestanden sind. Pull Requests deployen nicht.
Gebaut wird ausschließlich eingecheckter Code. Daten bleiben im persistenten
Storage-Volume; Secrets kommen aus der Umgebung.

Server, DNS, GitHub-Secrets, Erstinstallation, Sicherungen und Übernahme lokaler
Daten: [docs/deployment.md](docs/deployment.md).

## Fachliche Dokumentation

- [Anzahlungen, Abschläge und Schlussrechnungen](docs/teilrechnungen.md)
- [Buchhaltung und EÜR: Umfang](docs/buchhaltung-umfang.md)
- [EÜR-Jahreswechsel](docs/euer-jahreswechsel.md)
- [EÜR-Änderungen 2026](docs/euer-aenderungsprotokoll-2026.md)
- [Pauschalen und Voraussetzungen](docs/euer-pauschalen.md)
- [Entwicklungsleitlinien](AGENTS.md)

Die JavaScript-Pakete werden lokal ausgeliefert; Versionen stehen in
`config/importmap.rb`. Der PDF-Viewer verwendet Mozilla PDF.js, die Druckaufteilung
Paged.js. Bibliotheken und zugehörige Lizenzdateien liegen in `vendor/javascript`.
Der E-Rechnungsviewer ist keine vollständige Prüfung gegen die XRechnungs-Geschäftsregeln.

## Unterstützen und Lizenz

Spenden: [GitHub Sponsors](https://github.com/sponsors/GitToTheHub).
Spender erhalten keine Gegenleistung.

© 2026 Manuel Beck. Alle Rechte vorbehalten. Der Code ist öffentlich einsehbar,
darf aber ohne ausdrückliche Erlaubnis nicht kopiert, verändert oder weiterverwendet werden.
