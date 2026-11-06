# Kleinunternehmerzentrale – Entwicklungsleitlinien

## Arbeitsweise und Pflege
- Lies bei jeder neuen Aufgabe zuerst die relevanten aktuellen Projektdateien und Tests. Frühere Chats und diese Übersicht ersetzen keine Prüfung des Quellcodes; die README enthält teilweise ältere Beschreibungen der Oberfläche.
- Halte diese Datei kompakt. Aktualisiere sie bei grundlegenden Änderungen an Anforderungen, Architektur oder Konventionen. Detailwissen gehört in vorhandene Fachdateien und Dokumentation; vorübergehende Arbeitsstände und persönliche Rechnungsdaten gehören nicht hierher.
- Bewahre bestehende, auch uncommittete Änderungen. Ändere echte Rechnungen oder Buchhaltungsdaten nur im ausdrücklich beauftragten Umfang; verwende für Tests ausschließlich Testdaten.

## Produktziel und Bedienung
- Aktueller Entwicklungsschwerpunkt: eine verständliche Buchhaltung für den persönlichen Betrieb des Nutzers. Tätigkeiten und tatsächliche Geschäftsfälle zuerst klären; keine weiteren Berufsgruppen oder Sonderfall-Automatiken auf Vorrat ergänzen. Vorhandene Daten und Funktionen erst nach Prüfung ihrer Nutzung vereinfachen. Nachvollziehbare Berechnungen und verständlicher Code haben Vorrang vor Funktionsumfang.
- Langfristiges Produktziel: kostenlose, spendenbasierte Anwendung für Kleinunternehmer in Deutschland, ohne Abo, Werbung oder Tracking. Aktuell hat die nachvollziehbare Nutzung im eigenen Betrieb Vorrang vor einer Abdeckung aller Berufsgruppen. Umfang und Vereinfachung: `docs/buchhaltung-umfang.md`.
- Erkläre Rechnungsstellung, Buchhaltung und EÜR in einfacher deutscher Sprache. Fachbegriffe wie Anlagegut werden kurz erklärt; Hinweise sollen konkret, knapp und nicht doppelt sein.
- Bevorzuge nachvollziehbare Auswahlmöglichkeiten und passende Folgefelder statt langer Formulare. Eine bewusste Auswahl darf nicht durch eine automatisch vorgewählte Ausgabenart ersetzt werden. Auswahl nach Bestätigung ausblenden, Zusammenfassung und Änderungsmöglichkeit erhalten; auch erneute Wahl desselben Wertes muss die Auswahl schließen.
- Formulare ruhig und übersichtlich halten: kurze Erklärungen direkt am passenden Feld, keine doppelten Hinweise oder vorsorglich reservierten Hinweisflächen. Bedienung und nötige Erklärungen müssen auch auf dem iPhone ohne Hover zugänglich sein.
- Auswahlkarten zeigen keine sichtbaren Radiokreise; Auswahl, Hover und Tastaturfokus werden an der ganzen Karte dargestellt. Native Radio-Semantik für Tastatur und Screenreader erhalten.
- Beschriftete Aktionsbuttons nutzen `button_label` mit passendem dekorativem Icon; sichtbare Texte und zugängliche Namen erhalten. Reine Symboltasten und Auswahlwerte brauchen kein zusätzliches Icon.
- Nutze vorhandene CSS-Komponenten, Icons und Stimulus-Muster für ein einheitliches, responsives und tastaturbedienbares Layout, einschließlich Checkboxen, Radios, Fokuszuständen und Dialogen.

## Technik und Architektur
- Rails 8.1 (oder neuer), Ruby gemäß `.tool-versions` (oder neuer), SQLite, ERB, Propshaft, Hotwire/Turbo und Stimulus über Importmap. Kein zusätzlicher Frontend-Build ist erforderlich.
- Ruby-Stil: `rubocop-rails-omakase` gemäß `.rubocop.yml`. Bestehende Rails-Konventionen und fachliche Services weiterverwenden.
- Modelle enthalten Validierungen und Datensatzregeln; fachliche Berechnungen liegen insbesondere in `app/services`. JavaScript steuert Interaktion, serverseitige Validierung bleibt maßgeblich.
- Daten sind einem `Workspace` zugeordnet. Zugriffe und Verknüpfungen stets auf den aktuellen Workspace begrenzen. Gastzugang per Cookie, optionale Benutzerkonten, Datenexport und vollständige Löschung erhalten; inaktive Gäste werden nach drei Monaten gelöscht.
- Geld serverseitig als Dezimalwerte berechnen, bestehendes `EuroAmounts` verwenden. Geldfelder in der Oberfläche deutsch mit zwei Nachkommastellen darstellen, z. B. `100,00`; gemeinsame JS-Preisparser nutzen. Ungültige Eingaben nicht still abschneiden oder als null interpretieren.

## Datenbank und Bestandsdaten
- Die Anwendung befindet sich noch in der Entwicklung und ist nicht öffentlich verfügbar.
- Aktuell existiert nur ein persönlicher Nutzeraccount mit echten Buchhaltungsdaten.
- Bestehende Rechnungs-, Buchhaltungs- und Nutzerdaten müssen bei Änderungen erhalten bleiben. Keine unbeauftragten Änderungen oder Löschungen dieser Daten.
- Neue gespeicherte Informationen müssen beim persönlichen Datenexport und bei der vollständigen Workspace-Löschung berücksichtigt werden.
- Während der Entwicklung dürfen unnötige Datenbankstrukturen, veraltete Funktionen und technische Altlasten bereinigt werden, sofern keine wichtigen Daten verloren gehen.
- Vor dem öffentlichen Start soll eine gezielte Bereinigung des Projekts erfolgen. Dabei können auch Migrationen konsolidiert werden, solange bestehende Daten sicher übernommen werden.
- Destruktive Datenbankänderungen und größere Datenmigrationen nur nach vorheriger Prüfung und mit geeigneter Datensicherung durchführen.

## Rechnungen – implementiert und zu erhalten
- Einzelne Leistungstage nur mit Von-Datum erfassen; ein optionales Bis-Datum muss danach liegen. Historische Rechnungen mit gleichen Daten müssen unverändert stornierbar bleiben.
- Positionsbeschreibungen nutzen den Action-Text-/Trix-Editor mit Fett, Kursiv, Aufzählungen, nummerierten und eingerückten Listen sowie Links. Linkziele im Klartextexport vollständig erhalten. HTML bleibt im bestehenden `InvoiceLine.details`-Feld; Dateien und Bilder werden auch bei Paste/Drop blockiert. Keine zusätzliche RichText-/Upload-Speicherung ohne konkreten Bedarf.
- Rechnungstitel sind bei allen Rechnungsarten optional. Die Leistungsbeschreibung gehört in die Positionen; die Auftragsverknüpfung ist vom Titel unabhängig.
- In der Oberfläche heißt die Auswahl „Rechnungsart“. `[Rechnungsart]` (weiterhin auch `[Rechnungstyp]`) im Nummernformat ergibt RE/ANZ/ABS/SR bzw. ST beim Storno sowie AN für Angebot und AU für Auftrag; ohne diesen Platzhalter bleibt das bisherige Stornoformat `ST-[Jahr]-[Fortlaufendenummer]` erhalten. Gespeicherte Nummern und Formate nicht automatisch umstellen.
- Nummernanzeige und Format-Popup werden von Rechnungen, Angeboten und Aufträgen geteilt. Angebots-/Auftragsformate liegen in `SalesDocument.data`; deren Jahreszähler bleiben getrennt. Bestehende Nummern bei normalen Inhaltsänderungen erhalten.
- Die Rechnungsvorschau öffnet im Dialog über dem Formular; vor dem Öffnen aktuelle Entwurfsänderungen speichern.
- Entwürfe, Vorschau, Festschreiben, Druck/PDF, XRechnung und Storno/Korrektur sind vorhanden. Festgeschriebene Rechnungen sind unveränderlich; reguläre Korrekturen laufen über die vorhandenen Verfahren.
- Entwurfs-Autospeicherung und mehrere Tabs dürfen keine abgeschlossenen Entwürfe wieder aktivieren oder Änderungen gegenseitig unbemerkt überschreiben. Strg+S/⌘+S speichert im Rechnungsformular den Entwurf statt der Browserseite.
- Verwende „Stundensatz“, nicht „Stundenlohn“. Der allgemeine Stundensatz steht unter „Deine Angaben“, der individuelle beim Kunden. Leer bedeutet beim Kunden: allgemeine Vorgabe verwenden; diese als grauen Platzhalter zeigen. Positionen dürfen abweichen, schreiben aber nicht heimlich die allgemeine Vorgabe um.
- Änderungen an gespeicherten Kundendaten werden erst bei Vorschau oder Festschreiben in einem Dialog zur Entscheidung gestellt, nicht während der Eingabe.
- EUR kann mit Auslandskunden vereinbart werden. Ein Währungswechsel rechnet Positionspreise nicht automatisch um; Fremdwährungsfälle benötigen nachvollziehbare Kursangaben für EUR-Werte.
- Die Rechnungserstellung unterstützt auch Regelbesteuerung; die normale Zahlungserfassung ist auf Kleinunternehmer ausgerichtet. Unterstützung einzelner Steuerfelder bedeutet keine vollständige Automatisierung aller Umsatzsteuerfälle.
- Rechnungen, Angebote und Aufträge verwenden das gemeinsame Formular `shared/business_document_form`; dokumentbezogene Felder und Aktionen bleiben passend zum jeweiligen Vorgang.
- Angebote und direkte Aufträge sind optional (`SalesDocument`). Eine direkte Anzahlung kann den vollständigen Auftrag mit gemeinsamem Prozent-/Festbetrag oder unterschiedlichen Anteilen je Position speichern (`order_snapshot.allocations`); vereinbarte Positionspreise bleiben unverändert. Angenommene Angebote und Aufträge mit Rechnungen bleiben unverändert. Neue Teilrechnungen verweisen auf den Auftrag; ältere Verknüpfungen über die erste Teilrechnung bleiben erhalten. Der Ablauf gilt für Kleinunternehmer in EUR. Schlussrechnungen speichern angerechnete Zahlungen unveränderlich und buchen nur den Restbetrag. Vorherige Teilrechnungen müssen bezahlt oder storniert sein; angerechnete Zahlungen erst nach Storno der Schlussrechnung ändern.
- „Betrag direkt erfassen“ erlaubt Teilrechnungen ohne Gesamtauftrag. Schlussrechnungen können bezahlte direkte Teilrechnungsgruppen desselben Kunden auswählen (`order_snapshot.settlement_invoice_ids`). Zahlungsreferenzen in `deducted_payments` verhindern auch dabei doppelte Anrechnung und sperren nachträgliche Änderungen bis zum Storno der Schlussrechnung.
- Der E-Rechnungsviewer verarbeitet Dokumente ausschließlich lokal im Browser, ohne Upload oder Archivierung. Diese Datenschutzeigenschaft erhalten.

## Umsatzsteuer
- Die Kleinunternehmerzentrale richtet sich zunächst ausschließlich an Kleinunternehmer nach § 19 UStG.
- Steuerliche Sonderfälle nur anhand tatsächlich benötigter Geschäftsfälle erweitern. Bei Auslandsleistungen insbesondere Reverse Charge und weitere Umsatzsteuerpflichten prüfen; Kleinunternehmerstatus oder vorhandene Eingabefelder begründen keine automatische Fallabdeckung.
- Nicht unterstützte Sachverhalte sichtbar erklären. Berechnungen erst nach fachlicher Prüfung ergänzen; keine pauschalen Vollständigkeitsversprechen.
- Die Kleinunternehmerregelung schließt eine Umsatzsteuerschuld in bestimmten Sonderfällen nicht aus. Ein Vorsteuerabzug ist bei Anwendung der Kleinunternehmerregelung grundsätzlich ausgeschlossen.
- Zwischen bereits implementierten und noch geplanten Funktionen ist zu unterscheiden.
- Eine spätere Erweiterung für regelbesteuerte Unternehmer ist denkbar, aber derzeit nicht Teil des Entwicklungsziels.
- Steuerliche Regeln sind anhand aktueller amtlicher Quellen zu prüfen.

## Buchhaltung und EÜR – implementiert und zu erhalten
- `/buchhaltung` zeigt Einnahmen, abziehbare Ausgaben und Gewinn direkt für das gewählte Kalenderjahr. Jahreswechsel per Dropdown ohne zusätzlichen Bestätigungsbutton. Keine gesonderte Liste unbezahlter Rechnungen in dieser Übersicht.
- „Buchung erfassen“ führt zu `/buchhaltung/new`; dort heißt die erste Auswahl „Buchungsart“. Betriebliche Zahlungen und Geld-/Sachbewegungen zwischen Privatbereich und Betrieb verständlich unterscheiden. Anlagegüter haben einen eigenen Einstieg.
- Bei Betriebsausgaben zuerst Ausgabenbereich und Ausgabenart wählen, dann weitere Angaben wie Datum. Amtliche EÜR-Bezeichnungen helfen bei der Zuordnung; Themenbereiche und Beispiele dienen der Orientierung. Die regelbasierte Textsuche ist eine optionale Hilfe, nicht der primäre Erfassungsweg.
- Rein private Zahlungen auf Privatkonten werden nicht erfasst. Privat bezahlte Betriebsausgaben bleiben Betriebsausgaben und erzeugen die zugehörige Einlage automatisch. Betriebliche Zahlungen für private Zwecke erzeugen Entnahmen. Automatische Bewegungen nicht zusätzlich manuell buchen.
- Einnahmen bieten unter „Zahlungsart“ Geschäftskonto, Privatkonto und Bargeld. Bei Bargeld Betriebskasse kurz erklären und Verbleib bewusst wählen; die drei Auswahlkarten bleiben auch nach der Wahl sichtbar und direkt wechselbar; direkte vollständige oder anteilige Privatübernahmen automatisch als Entnahme berücksichtigen. Spätere Übernahmen separat erfassen. Bestehende Kontozuordnungen nicht umdeuten.
- Bei gemischten Ausgaben Gesamtbetrag, betrieblichen Anteil und Begründung erhalten. Automatische Einlagen betreffen nur den betrieblichen Anteil; private Anteile betrieblicher Zahlungen werden als Entnahmen berücksichtigt. Erstattungen müssen die ursprüngliche Aufteilung und Abzugsregeln berücksichtigen.
- Anlagegüter, AfA, Zugang aus Privatvermögen, dauerhafte Privatentnahme und jährliche Privatnutzung sind verknüpft. Private Mitnutzung ist keine vollständige Entnahme des Gegenstands. Separate Sach-, Nutzungs- und Leistungsentnahmen bleiben möglich; Doppelansätze mit Anlagegutwerten verhindern bzw. kenntlich machen.
- EÜR richtet sich grundsätzlich nach Zahlungen, nicht allein nach ausgestellten Rechnungen. Summenimporte, verknüpfte Rechnungszahlungen, Erstattungen, AfA und steuerliche Ergänzungen dürfen nicht doppelt zählen. Informations-/Davon-Felder und berechnete Summen sind keine zusätzlichen gewinnwirksamen Buchungen.
- Zentrale Zuordnung: `EuerFields`, `EuerForm`, `EuerFormLabels`; Berechnung: `BookkeepingReport`, `EuerAssetReport` und Pauschalen-Services. Fachliche Zuordnungen nicht unabhängig in mehreren Oberflächen nachbauen.
- Der vollständige EÜR-Hauptvordruck ist für 2025 und 2026 abgebildet. Originalbezeichnungen und jahresrichtige Zeilen verwenden; technische Kennziffern/„Positionen“ nicht im normalen Buchungsablauf zeigen.
- „EÜR für ELSTER vorbereiten“ ist eine eigene, aus der Buchhaltung verlinkte Seite. EÜR-Vorbereitung und Übernahme zeigen ihre Bereiche offen statt in Details-Akkordeons. Keine direkte ELSTER-Übermittlung vorhanden.
- Allgemeine Betriebsangaben liegen jahresbezogen in `EuerStatement`, nicht im normalen Übernahmeformular. Gespeicherte Rechnungs-Absenderdaten können fehlende Angaben vorschlagen; vorhandene Jahresangaben haben Vorrang. Fehlende Angaben dürfen die laufende Buchhaltung nicht sperren.
- Manuelle/CSV-Summenübernahme und sevdesk-EÜR-PDF-Import mit prüfbarer Vorschau sind vorhanden. Einnahmen-, Ausgaben-, Gewinn- und Einlagen-/Entnahmensummen anzeigen; Import erst nach Bestätigung speichern. Summen ersetzen keine Belegaufbewahrung oder vollständige Einzelbuchungshistorie.

## Steuerjahre, Grenzen und geplante Funktionen
- Formulardefinitionen und steuerliche Berechnungsregeln getrennt prüfen. Änderungen anhand amtlicher Primärquellen recherchieren; keine vollständige steuerliche Unterstützung aus vorhandenen Eingabefeldern ableiten.
- Vorjahresstände und ungeprüfte Regeln für neue Jahre sichtbar kennzeichnen. Alte Buchungen nicht mit neuen Regeln umdeuten. Jahreswechselverfahren: `docs/euer-jahreswechsel.md`; Vergleich 2025/2026: `docs/euer-aenderungsprotokoll-2026.md`.
- Implementiert für 2025/2026: geprüfte Berufs-/Nebentätigkeits- und Kindertagespflegepauschalen sowie Tages-/Arbeitszimmerpauschalen unter ausdrücklichen Voraussetzungen. `EuerExpensePolicy` speichert die Jahreswahl. Pauschalen dürfen tatsächliche Kosten nicht doppelt abziehen oder Originalbuchungen verändern. Umfang und Grenzen: `docs/euer-pauschalen.md`.
- Noch nicht vollständig automatisiert: Land-/Forstwirtschaftspauschalen, gemischte Tätigkeiten und betriebsübergreifende Aufteilungen, abweichende Wirtschaftsjahre, Betriebsaufgabe/-übertragung und Mitunternehmer-Sonderfälle. Dokumentierbare Angaben und Prüfhinweise ersetzen diese Berechnungen nicht.
- KI-Unterstützung wurde auf später verschoben. Aktuell arbeitet die Ausgabenhilfe regelbasiert. Keine externen KI-Dienste, Schlüsselverwaltung oder Berufspflichtauswahl ohne neuen Auftrag einführen.

## Tests und Qualität
- Passende Modell-/Service-/Controller-Tests für Fachregeln und Regressionen ergänzen. Bei Geldberechnungen insbesondere Rundung, Grenzwerte, Jahresbezug, Doppelzählung und Workspace-Isolation prüfen.
- Rails: `PARALLEL_WORKERS=1 bin/rails test`. JavaScript: `node --test test/javascript/*.mjs`. Rails-Testläufe gegen dieselbe SQLite-Testdatenbank nicht gleichzeitig starten.
- UI-Abläufe mit den vorhandenen Capybara/Selenium-Systemtests prüfen: `bin/rails test:system` bzw. betroffene Dateien unter `test/system`. Chrome erforderlich; Screenshots liegen unter `tmp/screenshots`. Mobile Darstellung und reale Interaktionen prüfen, nicht nur HTML-Ausgabe.
- Ruby-Stil: `bin/rubocop`; zusätzlich `git diff --check`. `bin/ci` und `.github/workflows/ci.yml` definieren vollständige Prüfungen einschließlich Brakeman, Gem- und Importmap-Audit.
- Prüfungen dem Änderungsumfang anpassen. Bestandene Tests nicht unnötig wiederholen; reine Dokumentationsänderungen benötigen keine Anwendungstests. Ausstehende oder blockierte Prüfungen ausdrücklich benennen, niemals als bestanden darstellen.
