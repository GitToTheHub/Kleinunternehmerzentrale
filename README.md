# Kleinunternehmerzentrale

Rails application for Kleinunternehmerzentrale.

## Requirements

- Ruby 4.0.7 (selected for this project in `.tool-versions`)
- Bundler (install with `gem install bundler` if needed)

SQLite is used as the development and test database. Rails manages it locally; no separate database server is required.

## Setup

From the project directory, run:

```sh
bin/setup --skip-server
```

This installs the Ruby dependencies and prepares the database without starting the server.

## Run the application

```sh
bin/rails server
```

Then open <http://localhost:3000>.

## Rechnungen und E-Rechnungen

Unter **Rechnungen** kannst du eine Kleinunternehmer-Rechnung erstellen, drucken oder über den Browser als PDF speichern. Auf Wunsch kann die Rechnung auch als strukturierte XRechnung-Datei (XML) heruntergeladen werden. Die Rechnung wird ohne Umsatzsteuer erstellt; nutze diese Funktion daher nur, wenn du die Kleinunternehmerregelung anwendest.

Kleinunternehmer müssen seit dem 1. Januar 2025 E-Rechnungen empfangen können, sind aber von der Pflicht zum Ausstellen einer E-Rechnung ausgenommen. Die Hinweise im Rechnungsformular erläutern die übrigen Fälle und Übergangsfristen. Vor dem Einsatz mit echten Kundendaten benötigt die Anwendung noch Benutzerkonten und Zugriffsschutz.

## Run tests

```sh
bin/rails test
```
