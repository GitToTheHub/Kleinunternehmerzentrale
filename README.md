# Kleinunternehmerzentrale

Kostenlose, spendenbasierte Web-App für Kleinunternehmer in Deutschland. Sie erklärt Gründung,
Steuern und Pflichten in einfacher Sprache und hilft beim Schreiben von Rechnungen.
Ohne Abo, ohne Werbung, ohne Tracking.

## Funktionen
- Start-Leitfaden mit Schritten, die man nach und nach abhakt
- Rechnungen mit Druck/PDF und XRechnung-XML (Kleinunternehmer- und Regelbesteuerung)
- E-Rechnungsviewer für UBL-/CII-XML und ZUGFeRD-/Factur-X-PDF; Verarbeitung ausschließlich im Browser, ohne Upload oder Archivierung
- Stornorechnung zur Korrektur, Hinweis zu den Umsatzgrenzen (25.000 € / 100.000 €)
- Eigener Bereich pro Nutzer ohne Anmeldung (Cookie), später optional als Konto
- Automatische Löschung von Gast-Daten nach 3 Monaten Inaktivität
- Datenexport als ZIP (CSV und XML) und Löschen aller Daten

## Entwicklung
Voraussetzungen: Ruby (siehe `.tool-versions`), SQLite, Node.js (siehe `.nvmrc`) und libvips für die Bildverarbeitung.
Unter macOS installierst du libvips mit `brew install vips`; im Docker-Image ist es bereits enthalten.

    nvm install
    bundle install
    bin/rails db:setup
    bin/rails server
    bin/rails test
    node --test test/javascript/*.mjs
    bin/rails test:system
    bin/rubocop

Die lokal eingebundenen JavaScript-Pakete sind mit ihren Versionen in `config/importmap.rb`
vermerkt und werden von `bin/importmap audit` mitgeprüft.

Die Formular-Browsertests starten selbst einen Testserver und verwenden ausschließlich die
Testdatenbank. Dafür muss Chrome installiert sein; für die JavaScript-Tests wird Node.js benötigt.
Geprüft werden unter anderem Pflichtfelder, deutsche Datumsfelder, Vorschau, Entwürfe in mehreren
Tabs, Speicherfehler, Kundenwechsel, Positionen, Steuerberechnung und das mobile Layout.
Die Tests laufen auch in GitHub Actions und über `bin/ci`. Bei Browserfehlern liegen Screenshots
unter `tmp/screenshots`.

Der E-Rechnungsviewer ist unter `/e-rechnungsviewer` erreichbar. Der Browsercheck
`ruby test/browser/e_invoice_viewer_check.rb` benötigt einen laufenden lokalen Server
auf Port 3000 und Chrome (optional `VIEWER_BASE_URL`). Er verwendet nur lokale Testdateien.

Für die Extraktion eingebetteter XML-Dateien verwendet der Viewer lokal eingebundenes
[Mozilla PDF.js](https://github.com/mozilla/pdf.js), Version 6.5.438, Legacy-Build.
Bibliothek, Worker und Apache-2.0-Lizenz liegen in `vendor/javascript/pdfjs*`.
Die Bibliothek wird erst beim Öffnen einer PDF geladen; es gibt keinen CDN-Zugriff.
Der Viewer ist keine Prüfung gegen XML-Schema, EN 16931 oder die Geschäftsregeln von XRechnung.

## Deployment
Mit Kamal auf den Hetzner-Cloud-Server. `config/deploy.yml` verwendet standardmäßig
`test.kleinunternehmerzentrale.de` und den SSH-Schlüssel `~/.ssh/id_ed25519_hetzner`.
`DEPLOY_SERVER_IP` und `APP_DOMAIN` können die Vorgaben überschreiben.
Docker muss lokal laufen. Kamals lokale Registry auf `127.0.0.1:5555` überträgt Images
über einen SSH-Tunnel; ein GitHub-Registry-Token ist nicht erforderlich.
Der Build enthält den aktuellen Arbeitsstand einschließlich uncommitteter Änderungen.
Lokale Datenbanken, Uploads und Secrets sind durch `.dockerignore` ausgeschlossen.

E-Mail-Vorgaben: `SMTP_ADDRESS=mail.your-server.de`, `SMTP_PORT=587` (STARTTLS),
`SMTP_USERNAME=service@kleinunternehmerzentrale.de` und
`MAIL_FROM="Kleinunternehmerzentrale <service@kleinunternehmerzentrale.de>"`.
Diese Werte sind über Umgebungsvariablen überschreibbar. Das Postfach-Passwort kommt
aus `SMTP_PASSWORD` oder der lokalen Datei `.kamal/smtp_password` (Dateirechte `600`).
Diese Datei ist von Git und Docker ausgeschlossen. Niemals Passwörter einchecken.

    bin/kamal setup
    bin/kamal deploy

Beim Fortsetzen eines abgebrochenen Deployments ohne neuen Build zuerst `bin/kamal registry setup`
ausführen, damit die lokale Registry nach einem Docker-Neustart wieder läuft.
Auf dem Testserver wird der klassische Docker-Imagespeicher `overlay2` verwendet
(`/etc/docker/daemon.json`: `features.containerd-snapshotter=false`), nachdem der
containerd-Import auf der frischen Installation wiederholt blockierte.

Die SQLite-Datenbank liegt im Docker-Volume `kleinunternehmerzentrale_storage`, im Container
unter `/rails/storage`. Täglich entsteht eine Sicherungskopie in `storage/backups`.
Zusätzlich sollten Server-Backups beim Hoster aktiviert sein.

## Unterstützen
Das Projekt finanziert sich über Spenden: [GitHub Sponsors](https://github.com/sponsors/GitToTheHub).
Spender erhalten keine Gegenleistung.

## Hinweis
Die Texte der App sind allgemeine Informationen und keine Steuer- oder Rechtsberatung.

## Lizenz
© 2026 Manuel Beck. Alle Rechte vorbehalten. Der Code ist öffentlich einsehbar, darf aber ohne ausdrückliche
Erlaubnis nicht kopiert, verändert oder weiterverwendet werden.


### Buchhaltung, Anlageverzeichnis und EÜR

Unter `/buchhaltung` verwalten Nutzer Einnahmen, Ausgaben, private Geldbewegungen sowie Sach-, Nutzungs- und Leistungsentnahmen und eingelegte Waren. Einnahmen und Ausgaben erhalten steuerliche Kategorien. Bruttobeträge und enthaltene Umsatzsteuer bzw. abziehbare Vorsteuer werden getrennt ausgewiesen. Geschäftliche Bewirtung wird standardmäßig zu 70 % berücksichtigt; bei anderen beschränkten Ausgaben muss der Nutzer den zulässigen Anteil bestimmen. Rückzahlungen vermindern die ursprüngliche Kategorie. Rechnungen erzeugen keine automatische Buchung.

Zahlungen über ein Privatkonto erzeugen zusätzlich eine Entnahme (Einnahme) oder Einlage (Ausgabe), jeweils im tatsächlichen Zahlungsjahr. Ein optionales abweichendes Steuerjahr ermöglicht fachlich geprüfte Zuordnungen nach gesetzlichen Ausnahmen, etwa der Zehn-Tage-Regel. Sachentnahmen erhöhen die Einnahmen und die Entnahmensumme. Eingelegte Ware erhöht die Einlagensumme und die Warenkosten; eingelegte Anlagegüter werden ausschließlich im Anlageverzeichnis erfasst.

Unter `/anlagegueter` werden angeschaffte und eingelegte Anlagegüter mit Kosten/Einlagewert, Nutzungsdauer und Abgängen verwaltet. Die lineare AfA läuft monatsanteilig vom Zugangsmonat bis zum Ende der Nutzungsdauer bzw. zum Abgang. Rundung erfolgt auf Cent; der Schlussbuchwert wird null. Selbständig nutzbare bewegliche GWG können sofort abgezogen werden. Der GWG-Prüfwert ohne enthaltene Umsatzsteuer muss ausdrücklich angegeben werden und darf 800 Euro nicht übersteigen, auch wenn der steuerliche Bruttokostenabzug beim Kleinunternehmer höher ist.

Individuelle Jahresbeträge ersetzen die automatische AfA. Bei degressiver Abschreibung, abweichender Bemessungsgrundlage, Sonderabschreibungen oder einem anderen Verlauf verwendet der Nutzer eine fachlich bestimmte manuelle Jahresfolge. Sonderabschreibungen erfordern die manuelle Methode, damit Begünstigungszeitraum und anschließende Restwert-AfA nicht pauschal angenommen werden. Jahresbeträge über dem verfügbaren Buchwert oder doppelte Jahre werden abgelehnt. Sonderabschreibungen werden im Anlageverzeichnis und in der EÜR getrennt ausgewiesen. Bei Verkauf wird nur der Restbuchwert automatisch gebucht; die tatsächliche Einnahme ist separat zu erfassen. Bei Privatentnahme werden steuerlicher Entnahmewert und ggf. Umsatzsteuer automatisch als Einnahme und Entnahme ausgewiesen. Bei nicht abnutzbaren Gütern wird der Restbuchwert bei Verkauf erst im angegebenen Zuflussjahr abgezogen.

Die Jahresübersicht und der CSV-Export enthalten Kategorien, Gewinnberechnung, Entnahmen/Einlagen, Anlageverzeichnis sowie Summen für die Anlage AVEÜR. Zeilen und Kennziffern sind explizit für **2025 und 2026** hinterlegt und anhand der amtlichen BMF-Vordrucke geprüft. Für andere Jahre zeigt die App einen Hinweis und keine ungeprüften Formularreferenzen. Unterstützt wird die Vorbereitung für Einzelunternehmen mit kalendergleichem Wirtschaftsjahr. Betriebliche Stammdaten und die geprüften Beträge werden manuell nach Mein ELSTER übertragen. Der Export ist keine ELSTER-Importdatei.

Steuerliche Ergänzungen ermöglichen begründete Pauschalen und Gewinnkorrekturen, z. B. Tagespauschale, Investitionsabzug, Steuerbefreiungen oder Hinzurechnung nicht abziehbarer Schuldzinsen. Positive Beträge erhöhen die gewählte Formularposition; negative vermindern sie. Die App weist bei übrigen Schuldzinsen über 2.050 Euro auf die Prüfung der Anlage SZ hin; sie berechnet die Anlage SZ mit Vorjahreswerten nicht automatisch. Sammelposten, Rücklagen und Sonderfälle werden nicht automatisch steuerlich beurteilt. Eine direkte Ergänzung zur AfA verändert nur die EÜR, nicht die Buchwerte: Für erfasste Güter ist stets der Jahresbetrag im Anlagegut zu pflegen. Die App prüft keine steuerliche Vollständigkeit und ermittelt weder Teilwerte noch Nutzungsdauern oder die Berechtigung zu Steuervergünstigungen automatisch.

Der persönliche ZIP-Export enthält Buchhaltung, Anlagegüter, manuelle Abschreibungen und Ergänzungen. Das Löschen eines Bereichs oder die Bereinigung abgelaufener Gastbereiche löscht auch diese Datensätze. Alle Zugriffe werden auf den eigenen Workspace eingeschränkt.

Unter „Bisherige Buchhaltung übernehmen“ können geprüfte EÜR-Positionssummen ab Jahresbeginn bis zu einem Stichtag übernommen werden. Unterstützt sind die direkte Eingabe und eine CSV mit `Position;Betrag` (Positionsschlüssel oder vollständige Kategorienamen, deutsche Dezimalbeträge, UTF-8 oder Windows-1252); eine Vorlage ist im Formular verfügbar. Die Vorschau ist 30 Minuten gültig und an den Workspace gebunden. Erst nach Bestätigung werden alle Summen gemeinsam gespeichert. Pro Jahr ist eine Übernahme möglich; bestehende oder neue Einzelvorgänge im übernommenen Zeitraum werden zur Vermeidung von Doppelzählungen abgelehnt. Die Übernahme kann vollständig zurückgenommen werden, ohne spätere Vorgänge zu löschen. Jahres-CSV und ZIP-Datenexport enthalten Herkunft und Zeitraum.

Textbasierte sevdesk-EÜR-PDFs können lokal über `pdftotext` (Poppler) eingelesen werden. Für macOS wird `brew install poppler` benötigt; das Docker-Image enthält `poppler-utils`. Der Import ist auf 10 MB, 20 Seiten und begrenzte Prozesslaufzeit/-ausgabe beschränkt. Er prüft vollständige Seitenangaben, Berichtsjahr und PDF-Stand, ordnet nach EÜR-Bereich und Positionsnummer zu und gleicht Einnahmen-, Ausgaben- und Gewinnsummen ab. Abweichende Zeilennummern älterer Formularlayouts werden ausdrücklich ausgewiesen. Unbekannte, doppelte oder widersprüchliche Positionen führen zum Abbruch ohne Teilübernahme. OCR für gescannte PDFs ist nicht enthalten. Der PDF-Stand liefert nur einen vorgeschlagenen, in der signierten Vorschau änderbaren Stichtag. Die Hinweise werden zusammen mit der Übernahme gespeichert und exportiert. Hochgeladene Dateien werden nicht dauerhaft archiviert. Alle EÜR-Eingabebereiche sind ohne Aufklappen sichtbar.

DATEV-Buchungsstapel werden nicht automatisch eingelesen: Letztere können Belegbuchungen und offene Posten statt tatsächlicher EÜR-Zahlungen enthalten. Die Hilfe beschreibt den allgemeinen Wechsel zu einem frei gewählten Stichtag, die Datensicherung und den Umgang mit offenen Rechnungen; ein eigener Abschnitt erläutert die Exportmöglichkeiten und den eingeschränkten Zugriff bei sevdesk. Anlagegüter und AVEÜR-Buchwerte werden nicht durch Summenimporte angelegt; Überschneidungen mit automatisch berechneten Anlagenwerten einschließlich privater Einlagen/Entnahmen werden abgefangen. Beim vollständigen Übertragen alter Anlagegüter müssen deren Beträge aus den Summen herausgenommen und die historischen Abschreibungen separat gepflegt werden.

Quellen:

- [BMF: Anlage EÜR 2025 mit Anlagen und Anleitung](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2025-08-29-anlage-EUER-2025.pdf?__blob=publicationFile&v=3)
- [BMF: Anlage EÜR 2026 mit Anlagen und Anleitung](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2026-09-01-anlage-EUER-2026.pdf?__blob=publicationFile&v=4)
- [§ 6 EStG: Einlagenbewertung und GWG](https://www.gesetze-im-internet.de/estg/__6.html)
- [§ 7 EStG: AfA](https://www.gesetze-im-internet.de/estg/__7.html)
- [§ 7a EStG: Sonderabschreibungen](https://www.gesetze-im-internet.de/estg/__7a.html)

Direkte ELSTER-Übermittlung ist weiterhin nicht implementiert. Der offizielle Integrationsweg ist [ELSTER ERiC](https://www.elster.de/elsterweb/infoseite/entwickler). Dafür werden Entwicklerregistrierung, Hersteller-ID und SDK-Zugang benötigt. Danach sind native SDK-Anbindung, jahresspezifische XML-Schemata, Authentifizierung, Testübermittlung, Nutzerfreigabe und Übermittlungsprotokolle zu implementieren. Die menschlich lesbaren Formular-Kennziffern sind kein Ersatz für ERiC-Schemata.

### Persönlicher Arbeitsablauf

Alle Funktionen für Ausland/Fremdwährungen, Anlagegüter, gemischte Nutzung und steuerliche Ergänzungen sind direkt verfügbar. Tätigkeitsprofile und Buchungshilfe sind vorerst entfernt.
Die Abrechnungsarten werden direkt im Rechnungsformular bei den Positionen eingestellt (aufklappbar über „Abrechnungsarten einstellen“). Standard sind Stunden und Pauschalpreise. Speichern aktualisiert die Auswahl ohne Seitenwechsel und erhält bestehende Positionen. `/einstellungen/edit` leitet auf diesen Bereich weiter.
Die Buchhaltung zeigt Einnahmen, Ausgaben, Privateinlagen und Entnahmen getrennt; automatische Geldbewegungen verlinken auf ihre Quelle.

Bei laufenden gemischten Ausgaben werden Gesamtbetrag, betrieblicher Prozentsatz und Begründung
gespeichert. Der betriebliche Anteil wird vor gesetzlichen Abzugsbeschränkungen berechnet.
Privat bezahlte Ausgaben erzeugen nur für den betrieblichen Anteil eine Einlage; vom Betriebskonto
bezahlte Privatanteile erzeugen eine Entnahme. Rückzahlungen übernehmen die ursprüngliche Aufteilung.
Rein private Zahlungen auf Privatkonten werden nicht erfasst.

Bei Anlagegütern werden Sacheinlage (Zugang aus Privatvermögen), jährliche private Mitnutzung und
dauerhafte Privatentnahme direkt beim Gegenstand verwaltet. Separat können Sacheinlagen von Waren und Verbrauchsmaterial sowie Sach-, Nutzungs- und
Leistungsentnahmen einschließlich privater Fahrzeugnutzung erfasst werden. Ein beim Anlagegut
berücksichtigter Privatnutzungswert darf nicht zusätzlich separat gebucht werden. Vorhandene manuelle Nutzungsentnahmen bleiben erhalten.

`AssetPrivateUse` speichert je Anlagegut und Jahr Nutzungsanteil, Grundlage und Berechnungsmethode.
Für gewöhnliche Geräte, Möbel und Software wird der private Anteil der regulären Jahresabschreibung
als Nutzungsentnahme berücksichtigt: volle AfA und Buchwerte bleiben erhalten, der Privatanteil erhöht
die EÜR-Einnahmen und Entnahmen. Fahrzeuge, Immobilien, Vorsteuer- und Sonderabschreibungsfälle
benötigen einen fachlich ermittelten Jahreswert. Laufende Kosten werden weiterhin beim jeweiligen
Ausgabeneintrag aufgeteilt und dürfen im manuellen Jahreswert nicht nochmals enthalten sein.
Jahreswerte werden nicht ungeprüft in Folgejahre übernommen. Frühere allgemeine Nutzungsangaben
bleiben reine Dokumentation und lösen keine rückwirkende Berechnung aus. Hinweise machen auf fehlende
Jahresangaben und mögliche Doppelzählung mit früheren manuellen Nutzungsentnahmen aufmerksam.
Die App entscheidet nicht über die Zuordnung zum Betriebsvermögen. Jahreswerte stehen im EÜR-CSV
und in `anlagegueter-private-nutzung.csv` des persönlichen Datenexports.

Steuerliche Grundlage: [EStH 2025, R 4.7](https://usth.bundesfinanzministerium.de/esth/2025/A-Einkommensteuergesetz/II-Einkommen-2-24b/3-Gewinn-4-7i/Paragraf-4/paragraf-4.html?nn=463862).

### Vollständiger EÜR-Hauptvordruck

`EuerForm` bildet sämtliche Zeilen des vierseitigen Hauptvordrucks für 2025 (1–107) und
2026 (1–108) ab. `EuerFields` enthält alle einzutragenden Betragsfelder mit Wirkung und
jahresabhängiger Zuordnung; `EuerFormLabels` die amtlichen Bezeichnungen. Die Ansicht unter
`/euer/edit?year=2026` zeigt auch Nullwerte, allgemeine Angaben, berechnete Summen und Überträge.
Summenzeilen sind nicht als zusätzliche Buchung erfassbar. Eingabefelder ohne eigene Kennziffer
(z. B. einzelne LuF-Überträge) erhalten keine erfundene Positionsnummer.

Die Übernahme und steuerlichen Ergänzungen unterstützen alle Hauptvordruck-Betragsfelder,
auch Regelbesteuerung, Landwirtschaft sowie Rücklagen und Ausgleichsposten. Die normale
Zahlungserfassung bleibt auf Kleinunternehmer ausgerichtet. Zeile 13 und die Davon-Angabe zu
Grundstücksaufwendungen sowie die Gesamtbeträge für InvStG/Teileinkünfteverfahren sind
informativ und erhöhen Gewinn oder Kosten nicht erneut. In Übernahmen dürfen Davon-Angaben
ihre zugehörigen Gesamtbeträge nicht übersteigen; spätere Ergänzungen werden darauf geprüft
und gegebenenfalls mit einem Hinweis versehen. Bildung/Übertragung von Rücklagen und
Ausgleichsposten erhöht die Ausgabenposition über deren berechnete Gesamtsumme genau einmal;
die Auflösung erhöht die Einnahmen entsprechend genau einmal.

`EuerStatement` speichert die allgemeinen Angaben je Workspace und Steuerjahr. Auch die
Übernahme kann Betriebsangaben enthalten. Gesondert gespeicherte Jahresangaben haben Vorrang.
Diese Angaben stehen im vollständigen Jahres-CSV sowie in den JSON-Dateien des ZIP-Exports.
Abweichende Wirtschaftsjahre können dokumentiert werden, stellen die kalenderjährliche
Buchungs- und Abschreibungsberechnung aber nicht automatisch um; die Ansicht weist ausdrücklich
auf die erforderliche zeitliche Abgrenzung hin. AVEÜR, SZ, LuF und die Mitunternehmer-Anlagen
sind eigenständige Vordrucke: Die bestehende AVEÜR-Hilfe bleibt verfügbar; weitere Anlagen
werden nicht automatisch erstellt, ihre geprüften Überträge sind im Hauptvordruck erfassbar.
Eine direkte ELSTER-Übermittlung erfolgt nicht.

### Gemeinsame Buchhaltungsübersicht

`/buchhaltung` zeigt Einnahmen, abziehbare Ausgaben und Gewinn/Verlust für das ausgewählte
Kalenderjahr direkt in der Übersicht. Anlagegüter, Abschreibungen, Einlagen, Entnahmen und
steuerliche Ergänzungen sind auf derselben Seite zugänglich und können während des Jahres
gepflegt werden. Die Beträge berücksichtigen alle erfassten Angaben; sie sind kein Abschlussstatus.
Die Übertragungshilfe für EÜR/AVEÜR und der CSV-Export liegen im aufklappbaren Bereich
„EÜR für ELSTER vorbereiten“. Die frühere Adresse `/buchhaltung/jahresabschluss` leitet unter
Beibehaltung des Jahres auf die gemeinsame Übersicht um. Summenübernahmen und steuerliche
Ergänzungen führen nach dem Speichern ebenfalls dorthin.

„Eintrag erfassen“ öffnet `/buchhaltung/new`. Die sechs Buchungsarten werden dort als
Auswahlfelder in drei Gruppen angezeigt, anstelle des bisherigen Dropdowns. Ohne Vorauswahl
erscheinen die Eingabefelder erst nach der Wahl einer Buchungsart. Direkte Links mit `kind`,
Rechnungszahlungen und der Geräte-Einstieg wählen den passenden Vorgang vor.

Das Zahlungsformular gruppiert Ausgabezwecke im Dropdown nach Themen wie Telefon/Software,
Büro/Räume, Waren/Versand, Dienstleistungen, Reisen, Werbung und Finanzen. Neue Betriebsausgaben beginnen ohne vorausgewählten Zweck; dieser muss
vor dem Speichern gewählt werden. Bestehende Zuordnungen bleiben erhalten. Besondere Abzugsregeln
und ein abweichendes Steuerjahr sind bei Bedarf aufklappbar. Bei gemischten laufenden Kosten zeigt
eine Vorschau die Aufteilung und die zusätzlich berücksichtigte Einlage oder Entnahme.

Unter `/buchhaltung/geraete` führt ein schreibgeschützter Einstieg durch Anschaffung, vorhandenes Gerät,
Telefon-/Internetvertrag und Reparatur. Betriebliche laufende Kosten führen in das Ausgabenformular,
vollständig betrieblich zugeordnete Geräte ins Anlageverzeichnis. Ungeklärte Zuordnungen und Geräte
im Privatvermögen führen nicht zu einer pauschalen Buchung des Kaufpreises. Die Einordnung ist keine
automatische steuerliche Beurteilung. Der Einstieg speichert keine Buchung und legt keinen Workspace an.

### Lokale Suche nach Ausgabenkategorien

Bei Betriebsausgaben steht die Kategorienliste zuerst. Die optionale Suche „Was möchtest du buchen?“ lässt sich darunter über „Hilfe bei der Zuordnung“ aufklappen und hilft mit Kategorien, Beispielen und Synonymen. Die Suche läuft im Browser, übermittelt keinen Text und setzt die Kategorie erst nach Auswahl eines Treffers. Alle Ausgabenarten bleiben über die Bereiche erreichbar. Bei Geräten wie Computern wird zwischen eigener Nutzung (direkt im Anlageverzeichnis) und Weiterverkauf (Wareneinkauf zur Auswahl) unterschieden. Die Suche verändert weder Beschreibung noch Betrag, Datum oder Zahlungskonto. Suchbegriffe sind in `ExpenseSearchHelper` zentral ergänzbar; sie bilden keine automatische steuerliche Entscheidung ab.

### EÜR-Positionen bei Betriebsausgaben

Bei Betriebsausgaben wählt man zuerst einen Bereich und danach die passende Ausgabenart über Karten wie bei der Eintragskategorie. Die Karten werden nach der Auswahl zu einer Zusammenfassung; über „Ausgabenbereich ändern“ oder „Ausgabenart ändern“ kann die Auswahl erneut geöffnet werden. Nur die Positionen dieses Bereichs erscheinen. Die EÜR-Bezeichnungen bleiben erhalten; kurze Beispiele erklären die gewählte Art. Zeilennummern und Kennzahlen stehen in der EÜR-Jahresübersicht, nicht im Buchungsformular. Jede auswählbare Ausgabenart verweist bereits auf eine EÜR-Kennzahl; die Änderung betrifft die Darstellung, nicht gespeicherte Buchungen oder die Gewinnberechnung.

Maßgeblich für die EÜR bleibt das Zahlungsjahr oder das ausdrücklich abweichende Steuerjahr. Die optionale Suchhilfe wählt Bereich und Ausgabenart gemeinsam, nachdem der Nutzer einen Treffer bestätigt. Beim Bearbeiten eines vorhandenen Eintrags wird der passende Bereich vorbelegt. Abschreibungen und steuerliche Ergänzungen behalten ihre eigenen Erfassungswege, um Doppelbuchungen zu vermeiden.

Die normale EÜR-Anzeige verwendet Zeile und amtliche Bezeichnung ohne technische Kennziffern. Diese bleiben im PDF-Import und Datenexport verfügbar. Die Formulargrundlage nennt ausdrücklich das Jahr und aktualisiert sich beim Jahreswechsel. Bei einem nicht unterstützten angefragten Jahr weisen Import- und Ergänzungsformulare ausdrücklich auf das stattdessen ausgewählte Formularjahr hin; Berichte geben keine Vorjahreszuordnung als gültig für ein unbekanntes Jahr aus. Hinweise zu abweichenden PDF-Zeilennummern nennen das erkannte Formularjahr.
