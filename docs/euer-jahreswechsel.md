# EÜR beim Jahreswechsel prüfen

Vorliegender Jahresvergleich:
[Änderungsprotokoll EÜR 2026 gegenüber 2025](euer-aenderungsprotokoll-2026.md).

Formular und Berechnungsregeln werden getrennt gepflegt. Ein neues Formularjahr
in `EuerFields` bestätigt keine steuerlichen Berechnungsregeln.

1. Amtlichen Vordruck und Anleitung mit dem Vorjahr vergleichen: Bezeichnungen,
   Zeilen, Kennzahlen, neue oder entfallene Felder und Summenüberträge.
2. Gesetzesänderungen einschließlich unterjähriger Stichtage prüfen. Insbesondere
   Abzugsanteile, Grenzen, Abschreibungen und branchenspezifische Sonderfälle
   unabhängig von Änderungen am Formular untersuchen.
3. `EuerTaxRules::YEARS` für das neue Jahr ausdrücklich ergänzen. Der derzeitige
   Abgleich umfasst nur Bewirtungsanteil, GWG-Grenze und Schuldzins-Schwelle;
   er bestätigt keine vollständige steuerliche Unterstützung. Grundlage für
   2025/2026 sind die jeweiligen amtlichen Anleitungen (Quellen in
   `EuerFields::SOURCES`), Abschnitte Bewirtung, GWG und Schuldzinsen.
   Zusätzlich die eigenständigen Jahresregeln für Berufs-, Kindertagespflege-
   und Arbeitszimmer-/Tagespauschalen prüfen; siehe
   [Umfang der Pauschalenberechnung](euer-pauschalen.md).
4. Bei Änderungen die betroffenen Berechnungen, Formularhinweise und PDF-/CSV-
   Importzuordnungen anpassen. Alte Jahresdefinitionen erhalten. Rückzahlungen
   müssen die Abzugsregel des ursprünglichen Eintrags behalten; Anschaffungen
   benötigen die für ihren maßgeblichen Zeitpunkt geltenden Regeln.
5. Vorjahresberechnungen, neues Jahr und Stichtagsfälle testen. Neue Felder dürfen
   alte Buchungen nicht umdeuten. Summenimporte mit Einträgen nicht doppelt zählen.

Ohne eigenen Jahreseintrag bleiben die bisherigen Berechnungswerte aus Gründen
der Kompatibilität verfügbar. Die Buchhaltungsübersicht weist ausdrücklich auf
den ungeprüften Stand hin. Das ist keine automatische Aktualisierung aus dem BMF-
Vordruck. Für neue zeitabhängige Regeln muss die Implementierung erweitert werden.
