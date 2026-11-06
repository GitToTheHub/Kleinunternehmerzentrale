# Automatische Pauschalen und verbleibende Sonderfälle

Stand: 20.10.2026. Die laufende Buchhaltung bleibt branchenunabhängig zugänglich.
Betriebsangaben dienen der Zuordnung und Prüfung, nicht als Zugangssperre.

## Automatische Berechnungen für 2025 und 2026

Unter **EÜR für ELSTER vorbereiten → Ausgabenmethode vergleichen und wählen**:

| Methode | Berechnung | EÜR-Position |
| --- | --- | --- |
| Hauptberufliche schriftstellerische/journalistische Tätigkeit | 30 % der maßgeblichen Einnahmen, höchstens 3.600 Euro | Betriebsausgabenpauschale, Zeile 24 |
| Begünstigte wissenschaftliche, künstlerische, schriftstellerische, Lehr-/Prüfungs-Nebentätigkeit | 25 %, höchstens insgesamt 900 Euro jährlich; ohne steuerfreie Übungsleitertätigkeit | Zeile 24 |
| Selbständige Kindertagespflege | Monatszeiträume, vereinbarte Wochenstunden, Freihalteplätze und deren tageweise Belegung; höchstens maßgebliche Einnahmen | Zeile 24 |
| Arbeit zuhause | 6 Euro je berücksichtigungsfähigem Tag, höchstens 1.260 Euro jährlich | Tagespauschale |
| Häusliches Arbeitszimmer | 1.260 Euro minus 105 Euro je vollem Monat ohne erfüllte Mittelpunktvoraussetzung | Arbeitszimmer |

Für die persönlichen und sachlichen Voraussetzungen werden ausdrückliche Angaben
und Bestätigungen benötigt. Die App leitet die Berechtigung nicht aus einem
Berufsnamen ab. Bei Kindertagespflege genügen anonyme Kind-/Platzkürzel.
Der BMF-Beispielfall vom 06.04.2023 wird in den Tests vollständig nachgerechnet.

## Keine doppelten Abzüge

Die gewählte Betriebsausgabenpauschale ersetzt im EÜR-Bericht die tatsächlichen
Ausgaben einschließlich AfA. Zahlungen, Einlagen/Entnahmen und Anlagebuchwerte
werden dadurch nicht gelöscht oder verändert. Der Wechsel zurück zu tatsächlichen
Ausgaben ist möglich. Eine zusätzliche automatische Pauschale zuhause wird bei
dieser Wahl abgewiesen.

Arbeitszimmer-/Tagespauschalen werden nicht neben bereits vorhandenen Ansätzen
derselben Kostenbereiche oder unklaren Überschneidungen mit doppelter
Haushaltsführung automatisch ergänzt. Bestehende manuelle Beträge werden nicht
still überschrieben. Bei später hinzukommenden Konflikten wird die automatische
Pauschale ausgesetzt und die fehlende Anwendung im Bericht sowie CSV erklärt.

Die zugrunde liegende jährliche Auswahl, Bestätigungen und Eingaben werden in
`euer-ausgabenmethoden.json` exportiert. Die EÜR-CSV dokumentiert Methode und
berechneten Betrag sowie die Berechnungsdaten für Kindertagespflege bzw. Arbeit
zuhause. Zwischen Steuerjahren wird keine Auswahl automatisch kopiert.

## Grenzen der automatischen Anwendung

Die automatische Pauschale für den gesamten Betrieb setzt ein eindeutig zugeordnetes Einzelunternehmen
mit Einkünften aus selbständiger Arbeit und kalendergleichem Wirtschaftsjahr
voraus. Weitere Einnahmearten, Gewinnkorrekturen oder unklare Erstattungen führen
zur gesonderten Prüfung. Bei Kindertagespflege können bereits in der EÜR
berücksichtigte sonstige steuerfreie Einnahmen von der Einnahmengrenze abgezogen
werden, beispielsweise enthaltene Versicherungsbeitragserstattungen.

Gemischte Tätigkeiten, Aufteilungen zwischen Betrieben oder einer Anstellung,
Methodenwechsel zuhause innerhalb eines Jahres und Änderungen der Betreuung
innerhalb eines Monats werden durch diese vereinfachten Eingaben nicht
automatisch aufgeteilt. Dafür bleiben fachlich ermittelte EÜR-Ergänzungen möglich.

Land-/Forstwirtschaftspauschalen, Sonderrechnungen für Mitunternehmer,
Betriebsaufgabe/Übertragung und abweichende Wirtschaftsjahre sind weiterhin keine
vollständig automatisierten Berechnungen. Die bestehenden Prüfhinweise und
Ergänzungsfelder ersetzen diese Berechnungen nicht. Die App ist damit nicht als
vollständige automatische Steuerberechnung für jede denkbare
Kleinunternehmer-Konstellation ausgewiesen.

## Jahreswechsel und Quellen

Neue Jahre benötigen eigene geprüfte Einträge in `EuerProfessionAllowance::RULES`,
`EuerDaycareAllowance::RULES` und `EuerHomeOfficeAllowance::RULES`. Für unbekannte
Jahre erfolgt keine automatische Anwendung dieser Pauschalen. Ergänzend gilt
der [Jahreswechsel-Leitfaden](euer-jahreswechsel.md).

- [Amtliche EÜR 2025 mit Anleitung](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2025-08-29-anlage-EUER-2025.pdf?__blob=publicationFile&v=3)
- [Amtliche EÜR 2026 mit Anleitung](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2026-09-01-anlage-EUER-2026.pdf?__blob=publicationFile&v=4)
- [BMF vom 06.04.2023 zur Kindertagespflege, veröffentlicht beim Finanzamt Deggendorf](https://www.finanzamt-deggendorf.de/fileadmin/RESSOURCEN/INFORMATIONEN/Steuerinfos/Zielgruppen/Familien/2023-04-06-ertragsteuerliche-behandlung-der-kindertagespflege.pdf)
- [§ 4 Abs. 5 Satz 1 Nr. 6b und 6c EStG](https://www.gesetze-im-internet.de/estg/__4.html)
