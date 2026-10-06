# Kleinunternehmerzentrale

Kostenlose, spendenbasierte Web-App für Kleinunternehmer in Deutschland. Sie erklärt Gründung,
Steuern und Pflichten in einfacher Sprache und hilft beim Schreiben von Rechnungen.
Ohne Abo, ohne Werbung, ohne Tracking.

## Funktionen
- Start-Leitfaden mit Schritten, die man nach und nach abhakt
- Rechnungen mit Druck/PDF und XRechnung-XML (Kleinunternehmer- und Regelbesteuerung)
- Stornorechnung zur Korrektur, Hinweis zu den Umsatzgrenzen (25.000 € / 100.000 €)
- Eigener Bereich pro Nutzer ohne Anmeldung (Cookie), später optional als Konto
- Automatische Löschung von Gast-Daten nach 3 Monaten Inaktivität
- Datenexport als ZIP (CSV und XML) und Löschen aller Daten

## Entwicklung
Voraussetzungen: Ruby (siehe `.tool-versions`) und SQLite.

    bundle install
    bin/rails db:setup
    bin/rails server
    bin/rails test
    bin/rubocop

## Deployment
Mit Kamal auf einen eigenen Server (z. B. Hetzner-VPS). Benötigte Umgebungsvariablen:
`DEPLOY_SERVER_IP`, `APP_DOMAIN`, `REGISTRY_USER`, `KAMAL_REGISTRY_PASSWORD` sowie für den E-Mail-Versand
(Passwort zurücksetzen) `SMTP_ADDRESS`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM`. Siehe `config/deploy.yml`.

    bin/kamal setup
    bin/kamal deploy

Die SQLite-Datenbank liegt im Volume `storage/`. Täglich entsteht eine Sicherungskopie in `storage/backups`.
Zusätzlich sollten Server-Backups beim Hoster aktiviert sein.

## Unterstützen
Das Projekt finanziert sich über Spenden: [GitHub Sponsors](https://github.com/sponsors/GitToTheHub).
Spender erhalten keine Gegenleistung.

## Hinweis
Die Texte der App sind allgemeine Informationen und keine Steuer- oder Rechtsberatung.

## Lizenz
© 2026 Manuel Beck. Alle Rechte vorbehalten. Der Code ist öffentlich einsehbar, darf aber ohne ausdrückliche
Erlaubnis nicht kopiert, verändert oder weiterverwendet werden.
