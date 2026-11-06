# Änderungsprotokoll: Anlage EÜR 2026 gegenüber 2025

Stand: 19.10.2026. Vergleichsgrundlage sind die unten verlinkten amtlichen
BMF-Vordrucke mit ihren Anleitungen. Zeilenangaben beziehen sich auf die
Hauptanlage EÜR, sofern keine andere Anlage genannt ist.

## Umfang und Prüfstand

Dokumentiert sind die für die App erfassten Änderungen der Hauptanlage,
ausgewählte unveränderte automatische Berechnungswerte und die Auswirkungen
auf Import und Buchhaltung. Dies ist kein vollständiger Vergleich aller
Steuergesetze, Anleitungen oder Sonderanlagen. Insbesondere folgt aus einem
unveränderten Formularfeld nicht, dass sämtliche zugehörigen Steuervorschriften
unverändert geblieben sind.

## Neue Ausgabenposition: Rücklage Tierbewertung

2026 enthält Zeile 27 erstmals die Bildung einer Rücklage zur Tierbewertung
bei Land- und Forstwirten, als Übertrag aus Zeile 18 der Anlage LuF.
Nach dem BMF-Begleitschreiben betrifft dies die erstmalige Anwendung der
aktualisierten Tierbewertungsrichtwerte im Wirtschaftsjahr 2026 oder 2026/2027;
auch Betriebe der gewerblichen Tierzucht werden dort genannt.

In der App ist die Position als `expense_livestock_reserve` ausschließlich für
2026 hinterlegt. Ein übernommener oder ergänzter Betrag erhöht die
Betriebsausgaben. Die Rücklagenhöhe und die Anlage LuF berechnet die App
nicht automatisch. Für einen Softwareentwicklungsbetrieb entsteht daraus
keine neue gewöhnliche Ausgabenart.

## Verschobene Zeilen und Überträge

| Inhalt | EÜR 2025 | EÜR 2026 | Bedeutung für die App |
| --- | --- | --- | --- |
| Allgemeine Angaben, Einnahmen und erste Ausgabenpauschalen | Zeilen 1–26 | Zeilen 1–26 | Zeilennummern bleiben gleich; einzelne Verweise ändern sich. |
| Bildung Rücklage Tierbewertung | nicht vorhanden | Zeile 27 | Neues Betragsfeld, nur 2026 verfügbar. |
| Waren, Rohstoffe und Hilfsstoffe einschließlich Nebenkosten | Zeile 27 | Zeile 29 | Gleicher interner Buchungsbereich, neue Zeile. |
| Erster Ausgabenübertrag | Zeile 28 | Zeile 28 | 2025: Pauschalen und Waren; 2026: Pauschalen und neue Rücklage, ohne Waren. |
| Fremdleistungen bis Einlagen | Zeilen 29–107 | Zeilen 30–108 | In diesem Abschnitt verschieben sich die bestehenden Zeilen um eins. |

Die neue Zeile bedeutet daher keine pauschale Verschiebung aller Zeilen:
Insbesondere Waren springen von 27 auf 29, während der Übertrag 28 bleibt.

Wichtige Einzelzuordnungen:

| Position | 2025 | 2026 |
| --- | --- | --- |
| Bezogene Fremdleistungen | 29 | 30 |
| Ausgaben für eigenes Personal | 30 | 31 |
| AfA auf bewegliche Wirtschaftsgüter | 33 | 34 |
| Geringwertige Wirtschaftsgüter | 36 | 37 |
| Telekommunikation | 43 | 44 |
| Laufende EDV-Kosten | 50 | 51 |
| Arbeitsmittel | 51 | 52 |
| Übrige Schuldzinsen | 56 | 57 |
| Übrige unbeschränkt abziehbare Betriebsausgaben | 60 | 61 |
| Bewirtungsaufwendungen | 63 | 64 |
| Summe Betriebsausgaben | 75 | 76 |
| Übertrag Summe Betriebseinnahmen | 76 | 77 |
| Abzüglich Summe Betriebsausgaben | 77 | 78 |
| Investitionsabzugsbeträge, Hinzurechnung aus drei Vorjahren | 84–86 | 85–87 |
| Investitionsabzugsbetrag nach § 7g Abs. 1 EStG | 88 | 89 |
| Hinzurechnung nicht abziehbarer Schuldzinsen | 96 | 97 |
| Entnahmen | 106 | 107 |
| Einlagen | 107 | 108 |

Die Verweise auf Summen und Rücklagenüberträge sind ebenfalls jahrbezogen:
Beispielsweise verweist die Einnahmenzeile 22 nun auf 106 statt 105 und die
Einnahmensumme in Zeile 23 auf 77 statt 76. Das BMF-Begleitschreiben nennt
für Körperschaften die Übermittlung bis Zeile 76 statt bisher 75.

## Jahresabhängige Beschriftungen

Die Hinzurechnungen von Investitionsabzugsbeträgen beziehen sich 2025 auf
2022, 2023 und 2024; im Formular 2026 auf 2023, 2024 und 2025. Die App bildet
diese Beschriftungen aus dem gewählten Steuerjahr. Auch Querverweise innerhalb
der Bezeichnungen werden auf die Zeilen des jeweiligen Jahres angepasst.

Bei den in der App hinterlegten Betragsfeldern der Hauptanlage ist gegenüber
2025 kein bestehender interner Feldschlüssel entfallen. Das ist keine Aussage
über sämtliche Sonderanlagen oder jede redaktionelle Änderung der Anleitungen.

## Abgeglichene automatische Berechnungswerte

| Regel | 2025 | 2026 | Prüfgrundlage |
| --- | --- | --- | --- |
| Abziehbarer Anteil angemessener geschäftlicher Bewirtung, bei erfüllten Voraussetzungen | 70 % | 70 % | Anleitungen zu Zeile 63 bzw. 64 |
| GWG-Wertgrenze nach Abzug einer enthaltenen Vorsteuer | 800 Euro | 800 Euro | Anleitungen zu Zeile 36 bzw. 37 |
| Schwelle für die Angaben der Anlage SZ bei Einzelunternehmen, ohne begünstigte Anlagefinanzierungszinsen | über 2.050 Euro | über 2.050 Euro | Begleitschreiben und Schuldzinsabschnitte der Anleitungen |

Diese Werte sind getrennt für 2025 und 2026 in `EuerTaxRules` hinterlegt.
Die Schuldzins-Schwelle löst einen Prüfhinweis aus; die App berechnet damit
keinen automatischen Hinzurechnungsbetrag. Die übrigen Voraussetzungen der
jeweiligen Regel werden dadurch nicht vollständig automatisiert geprüft.

## Auswirkungen auf bestehende Buchungen und Import

- Eine andere Zeilennummer verändert allein weder den Betrag noch die
  Abziehbarkeit einer bestehenden Ausgabe. Die internen Feldschlüssel bleiben
  bestehen, die Ausgabe erhält die zum Steuerjahr passende Formularzeile.
- Das neue Rücklagenfeld wird für 2025 nicht angeboten. Beträge dürfen nicht
  durch pauschales Verschieben aller Zeilennummern importiert werden.
- Der sevdesk-PDF-Import berücksichtigt bekannte Abweichungen zwischen
  Berichtsjahr und gedruckten Formularzeilen anhand von Bereich und Kennzahl.
  Erkennt er alte Zeilen, wird dies in der Importprüfung mitgeteilt. Unbekannte
  oder widersprüchliche Zuordnungen werden nicht stillschweigend übernommen.
- Ungeprüfte Formularjahre und ungeprüfte automatische Berechnungswerte
  werden ausdrücklich kenntlich gemacht. Die App aktualisiert sich nicht
  selbst aus einem neu veröffentlichten Vordruck.

## Hinterlegte Umsetzung und Kontrollen

- `EuerFields`: Feldverfügbarkeit und Zeilen für 2025/2026.
- `EuerForm` und `EuerFormLabels`: Überträge, Summen und Jahresbeschriftungen.
- `EuerTaxRules`: drei ausdrücklich abgeglichene automatische Werte je Jahr.
- `SevdeskEuerImport`: PDF-Zuordnung und Prüfung der importierten Summen.
- Tests in `complete_euer_test.rb`, `sevdesk_euer_import_test.rb` und
  `euer_tax_rules_test.rb`: Formularabdeckung, neue Position, Summenüberträge,
  Import und Hinweise zu ungeprüften Jahren.

Der [Ablauf für kommende Jahreswechsel](euer-jahreswechsel.md) bleibt separat
dokumentiert. Ein vollständiger fachlicher Abgleich aller Steueränderungen
und Sonderanlagen ist durch dieses Protokoll nicht als abgeschlossen markiert.

## Amtliche Quellen

- [BMF: Anlage EÜR 2025, Schreiben vom 29.08.2025 mit Vordrucken und Anleitungen](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2025-08-29-anlage-EUER-2025.pdf?__blob=publicationFile&v=3)
- [BMF: Anlage EÜR 2026, Schreiben vom 01.09.2026 mit Vordrucken und Anleitungen](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2026-09-01-anlage-EUER-2026.pdf?__blob=publicationFile&v=4)

Die Quellen wurden anhand der bereits lokal vorliegenden amtlichen PDFs
verglichen. Der erneute Abruf über die Websuche war am Prüfdatum mit HTTP 503
nicht verfügbar.
