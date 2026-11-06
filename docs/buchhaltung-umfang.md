# Verständliche Buchhaltung: Entwicklungsumfang

## Ziel

Die nächste Entwicklungsstufe unterstützt einen kleinen IT-Dienstleistungsbetrieb:
Softwareentwicklung, Webseiten- und Anwendungsbetreuung sowie IT-Support.
Jede Eingabe und jede Auswirkung auf die Jahressummen soll nachvollziehbar sein.
Die Anwendung bildet zunächst keine vollständige Buchhaltungssoftware für alle
Berufsgruppen ab. Persönliche Beträge, Verträge und Aufenthaltsdaten gehören
nicht in diese Dokumentation.

## Benötigter Kern

- Rechnungen erstellen und tatsächliche Kundenzahlungen zuordnen.
- Bezahlte betriebliche Kosten erfassen, insbesondere Hosting, Server,
  Software und Telekommunikation.
- Bei gemischten laufenden Kosten Gesamtbetrag, betriebliche Nutzung und
  deren Begründung erhalten; die Aufteilung sichtbar erklären.
- Betriebliche und private Zahlungen unterscheiden, auch bei einzelnen
  Geschäftsvorfällen auf dem Privatkonto. Automatische Einlagen und Entnahmen
  nicht ein zweites Mal erfassen.
- Geräte mit Anschaffungsdaten, bisherigem Kostenabzug und privater Nutzung
  nachvollziehbar verwalten. Neue Anschaffung und Übernahme eines bestehenden
  Geräts unterscheiden.
- Einnahmen, abziehbare Ausgaben und Gewinn je Kalenderjahr zeigen und die
  enthaltenen Buchungen sowie steuerlichen Anpassungen erklären.
- Geprüfte bisherige Jahressummen nach Vorschau übernehmen. Der letzte
  vollständig erfasste Zahlungstag bestimmt den Anschlusszeitraum; das
  Erstellungsdatum einer Auswertung ist dafür kein Beleg.
- Belegnummern als Verbindung zu getrennt aufbewahrten Originalbelegen nutzen.
  Die Anwendung enthält derzeit kein Belegarchiv.

## Bar erhaltene Kundenzahlungen

Die Zahlungsart unterscheidet Geschäftskonto, Privatkonto und Bargeld.
Bei Bargeld wird die Betriebskasse als betrieblicher Bargeldbestand erklärt.
Der Nutzer wählt bewusst, ob das Geld dort bleibt oder unmittelbar vollständig
bzw. teilweise privat übernommen wird. Die gesamte Zahlung bleibt eine
Betriebseinnahme. Nur der private Anteil erzeugt eine automatische Privatentnahme;
eine spätere Übernahme aus der Betriebskasse wird separat gebucht.

`BookkeepingEntry.payment_account = cash` speichert diese Zahlungsart;
`cash_usage` unterscheidet `business`, `private` und `split`.
`cash_private_amount` enthält den privaten Eurobetrag, bei `business` null Euro,
bei `private` den Gesamtbetrag. Bei `split` ist eine positive Teilmenge erforderlich.
Die Einlagen-/Entnahmenauswertung verwendet das tatsächliche Zahlungsjahr,
auch bei abweichendem Steuerjahr der Einnahme. Bei Rückzahlungen gibt die Auswahl
an, aus welchem Bereich das Bargeld zurückgezahlt wird. Bestehende Einträge mit
`business` oder `private` bleiben unverändert. Beide neuen Angaben sind in den
CSV-Exporten enthalten und werden mit dem Workspace gelöscht.

Die Auswahl ist in der Zahlungserfassung, bei Einnahmen in der Buchhaltung und
bei deren Rückzahlungen verfügbar. Sie führt kein Kassenbuch und berechnet keinen
laufenden Kassenbestand. Die Option „Bereits vollständig bezahlt“ bei der
Rechnungserstellung behält ihren bisherigen Ablauf; die neue Aufteilung kann
anschließend an der zugehörigen Buchung bearbeitet werden.

Fachliche Grundlage für Geldentnahmen aus der Kasse:
[ELSTER-Anleitung zur Anlage EÜR 2025, Entnahmen und Einlagen](https://www.elster.de/elsterweb/helpGlobal?themaGlobal=help_euer_ufa_77_2025).

## Grenzen und offene Prüfung

Berufspauschalen anderer Tätigkeiten, Kindertagespflege und landwirtschaftliche
Sonderfälle gehören nicht zum aktuellen Entwicklungsziel. Vorhandene Funktionen
werden nicht ungeprüft gelöscht: Zuerst Abhängigkeiten und gespeicherte Nutzung
prüfen, danach Oberfläche und gegebenenfalls Code gezielt reduzieren.

Ein Auslandsanbieter wird anhand der konkreten Rechnung beurteilt, nicht allein
anhand seines Markennamens. Steuerliche Ansässigkeit, Betriebsstätte und Arbeiten
im Ausland kann die Anwendung nicht aus einer deutschen Gewerbeadresse ableiten.
Diese Fragen müssen vor passenden steuerlichen Voreinstellungen geklärt werden;
sie verhindern nicht die technische Vereinfachung der Anwendung.

Bereits abgegebene Steuererklärungen und übernommene Buchhaltung werden nicht
automatisch korrigiert. Auffällige Einlagen, Entnahmen oder Anlagenwerte sind
anhand der ursprünglichen Vorgänge zu prüfen.

## Vorhandene technische Zuständigkeiten

- `BookkeepingEntry`: Zahlungen, Kontozuordnung und betriebliche Anteile.
- `BookkeepingReport`: Jahressummen und automatische Geldbewegungen.
- `BusinessAsset`, `AssetDepreciation`, `AssetPrivateUse`, `EuerAssetReport`:
  Geräte, Kostenverteilung und private Nutzung.
- `BookkeepingImport`, `SevdeskEuerImport`, `EuerTotalsImport`: geprüfte
  Summenübernahme ohne vollständige Einzelbuchungshistorie.
- `EuerFields`, `EuerForm`, `EuerFormLabels`: gemeinsame Zuordnung zur EÜR.
- `EuerExpensePolicy` und Pauschalen-Services: vorhandene Sonderberechnungen;
  kein Anlass, für den IT-Alltag weitere Pauschalen einzuführen.

Die Vereinfachung verwendet diese Zuständigkeiten weiter. Keine zweite
Berechnungslogik und kein zusätzliches Frontend-System einführen.
