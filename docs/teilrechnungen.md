# Anzahlungs-, Abschlags- und Schlussrechnungen

Stand: 01.11.2026. Unterstützt werden Aufträge in EUR nach § 19 UStG.

- Anzahlung: vereinbarte Zahlung vor Erbringung der entsprechenden Leistung.
- Abschlag: Zahlung auf den Auftrag nach Arbeitsfortschritt. Bei Werkverträgen richtet sich der gesetzliche Anspruch nach dem Wert der erbrachten, vertraglich geschuldeten Leistungen (§ 632a BGB).
- Schlussrechnung: vollständige Abrechnung des Auftrags unter Anrechnung erhaltener Zahlungen.
- Eine echte Teilrechnung rechnet eine gesondert vereinbarte, abgeschlossene Teilleistung endgültig ab. Hierfür dient die normale Rechnung; sie wird nicht in einer Schlussrechnung erneut berechnet.

## Beschreibung und Pflichtangaben bei einer Anzahlung

Für Kleinunternehmer nach § 19 UStG nennt § 34a UStDV insbesondere Namen und Anschriften beider Seiten, Steuernummer, Umsatzsteuer-ID oder Kleinunternehmer-ID des Ausstellers, Ausstellungsdatum, Art/Umfang der Leistung bzw. Art/Menge der Ware sowie den Rechnungsbetrag mit Hinweis auf die Steuerbefreiung. Bei der Anzahlung muss die zukünftig zu erbringende Lieferung oder Leistung ausreichend konkret erkennbar sein; „Anzahlung“ allein genügt nicht. Der Bezug kann in den Positionen stehen. Ein gesonderter Rechnungstitel oder ein vorher erstelltes Angebot ist dafür nicht erforderlich.

Gesamtauftragspreis und Prozentsatz sind hilfreiche Zusatzangaben, aber keine allgemeinen zusätzlichen Pflichtangaben der Anzahlungsrechnung. Beispiel: „Anzahlung für die vereinbarten Anpassungen am Teilnehmermanagement der Ruby-on-Rails-App. Gesamtpreis 800,00 Euro, davon 50 Prozent = 400,00 Euro.“ Abgerechnet werden dabei nur 400,00 Euro, nicht zusätzlich nochmals 800,00 Euro.

Die Oberfläche erklärt bei Punkt 4 den Gesamtumfang und die vereinbarten Preise. Die Auswahlkarten stehen vor den Positionen und sind bei Anzahlungs-/Abschlagsrechnungen ohne zusätzliche Aktivierungscheckbox sichtbar. Die gemeinsame Berechnung steht direkt unter dem einmal angezeigten Gesamtpreis. Einzelanteile stehen innerhalb der jeweiligen Position und wiederholen weder Titel noch Positionspreis. Standard ist „Gesamten Auftrag anteilig berechnen“: Ein gemeinsamer Prozentsatz oder Festbetrag genügt, ohne die einzelnen Positionen zu bewerten. Optional kann „Anteil je Position festlegen“ gewählt werden. Dann erhält jede Position direkt in ihren Eingabefeldern einen eigenen Prozentsatz oder Festbetrag; 0 lässt sie bei dieser Anforderung unberücksichtigt. Je Position wird auf Cent gerundet, anschließend werden die Beträge addiert. Die Rechnung enthält die tatsächlich angeforderten Positionsbeträge, der Auftrag behält seine vollständigen Preise.

`allocation_basis` und `position_allocations` sind virtuelle Formularattribute und werden roh im Entwurf gespeichert. Die serverseitige Berechnung speichert kanonische Positionsindizes, Berechnungsart, Eingabewert und Betrag in `order_snapshot.allocations`; `allocation_mode=positions` kennzeichnet Positionsanteile. Damit sind sie automatisch im Auftragsbezug-Export enthalten und beim Storno unverändert nachvollziehbar. Formulare indizieren Positionen bei der Entwurfsfortsetzung neu; die Anteile müssen dabei ihrer ursprünglichen Position zugeordnet bleiben.

Bereits angeforderte aktive Teilrechnungen verbrauchen den verfügbaren Positionsbetrag unabhängig vom Zahlungsstatus. Gesamtanzahlungen werden für diese Grenze anteilig auf die noch nicht abgerechneten Positionen verteilt; Centreste werden nach dem größten Rest verteilt. Bei älteren Gesamtanzahlungen ohne Positionsaufstellung wird die Verteilung aus den vollständigen Positionspreisen abgeleitet. Stornierte Rechnungen verbrauchen keinen Anteil. Gesamtsumme und Positionsgrenzen werden beim Festschreiben unter der Workspace-Sperre erneut geprüft.

Grundlagen: [§ 34a UStDV](https://www.gesetze-im-internet.de/ustdv_1980/__34a.html) und die Bestimmtheit der künftigen Leistung in UStAE 14.8 (amtliche Quellen unten). Die gesetzlichen Mindestangaben sind von zusätzlichen App-Feldern zu unterscheiden.

## Direkte Anzahlung und Auswahl für die Schlussrechnung

Die dritte Karte „Betrag direkt erfassen“ ist für Anzahlungen/Abschläge ohne gespeicherten Gesamtauftrag verfügbar. Die Positionen beschreiben nur die jetzt angeforderten Teilbereiche und Beträge. Es wird kein `SalesDocument` angelegt, `allocation_basis=direct` bleibt im Entwurf erhalten und `allocation_mode=direct` kennzeichnet die gespeicherte Rechnung. Der vollständige Umfang und Preis werden später in der Schlussrechnung erfasst. Bei bereits gespeicherten Gesamtaufträgen bleiben die bisherigen zwei Berechnungsarten maßgeblich.

Bei einer Schlussrechnung können bezahlte direkte Teilrechnungen desselben gespeicherten Kunden ausgewählt werden. Zusammengehörige Teilrechnungen werden als Gruppe vollständig übernommen; unbezahlte, stornierte, erstattete, bereits angerechnete oder fremde Gruppen stehen nicht zur Auswahl. Die Festschreibung prüft Verfügbarkeit, Kunde, EUR/Kleinunternehmerfall, Zahlungsdatum, Rückzahlungen und Restbetrag erneut unter der Workspace-Sperre. Zu einem bereits gewählten Auftrag gehörige Zahlungen bleiben automatisch enthalten; zusätzliche direkte Gruppen können ergänzt werden.

`settlement_invoice_ids` ist ein virtuelles Array für Formulare und Autospeicherung. Die gewählten Bezugsrechnungen werden in `order_snapshot.settlement_invoice_ids` gespeichert; `deducted_payments` enthält jede tatsächliche Rechnungszahlung genau einmal als unveränderliche Momentaufnahme. Aktive Schlussrechnungen werden zusätzlich über diese Zahlungsreferenzen gefunden, damit auch unabhängig erfasste direkte Anzahlungen vor doppelter Anrechnung sowie nachträglichen Zahlungsänderungen, Rückzahlungen und Storno geschützt bleiben. Erst das Storno der Schlussrechnung hebt diese Sperre auf. Der Auftragsbezug-JSON-Export enthält auch direkte Teil- und Schlussrechnungen ohne `SalesDocument`.

## Ablauf und Datenmodell

Angebote und Aufträge sind optional. Unter „Angebote & Aufträge“ kann ein Angebot als eigener, nummerierter Stand gespeichert und als Auftrag übernommen werden. Vereinbarte Aufträge können ohne vorheriges Angebot erfasst werden, zum Beispiel nach einer telefonischen Einigung. Beim Erstellen eines Auftrags können noch nicht übernommene Angebote ausgewählt und ohne erneute Eingabe als Auftrag übernommen werden. Die Rechnungsübersicht bietet auch Einstiege zum Erstellen von Angeboten und Aufträgen. Eine normale Rechnung benötigt weiterhin keinen Auftrag.

Bei einer direkten Anzahlungs-/Abschlagsrechnung ist die Berechnung aus dem Gesamtauftrag voreingestellt: Die Positionen enthalten den vollständigen Auftrag. Der jetzt angeforderte Anteil wird als Prozent oder Festbetrag gemeinsam unter dem Gesamtpreis oder direkt je Position gewählt. Bei 800 Euro und 50 Prozent entstehen 400 Euro Anzahlung und ein gespeicherter Auftrag über 800 Euro. Die Rechnungsposition fordert nur die 400 Euro an und nennt den Gesamtpreis sowie die vereinbarten Positionen. Deren ursprüngliche Preise bleiben im Auftrag und in `order_snapshot` erhalten. Die Vorschau speichert noch keinen Auftrag; erst das Festschreiben legt ihn gemeinsam mit der Rechnung an. Ohne diese Berechnung kann weiterhin nur der tatsächlich angeforderte Betrag in den Positionen erfasst werden.

`SalesDocument` speichert Angebote und Aufträge als eigenständige nummerierte Momentaufnahmen. Angebote erhalten AN-, Aufträge AU-Nummern mit eigenem Jahreszähler. Ein angenommenes Angebot bleibt erhalten; die Übernahme erzeugt genau einen verknüpften Auftrag. Angenommene Angebote und Aufträge mit Rechnungen sind nicht mehr bearbeitbar. Angebote und Aufträge allein erzeugen keine Buchhaltungseinträge. Rechnungen, Angebote und Aufträge verwenden dieselbe Formularbasis (`shared/business_document_form`) mit gemeinsamer Absender- und Kundenerfassung, Stundensätzen, Adresssuche und Positionseditor. Datumsfelder und Abschlussaktionen richten sich nach dem Dokument. Angebote und Aufträge werden ausdrücklich gespeichert; die Rechnungsentwürfe behalten die bestehende Autospeicherung.

Rechnungen mit gespeichertem Gesamtauftrag verweisen mit `sales_document_id` auf den Auftrag. Weitere Anzahlungen/Abschläge dürfen zusammen den vereinbarten Gesamtpreis nicht überschreiten. Nach einer Teilrechnung wird der Auftrag durch eine Schlussrechnung abgeschlossen; eine zusätzliche normale Vollrechnung ist gesperrt. Die vereinbarten Positionen werden serverseitig aus dem Auftrag geladen. Ältere Rechnungen behalten unverändert den Bezug über die erste Anzahlungs-/Abschlagsrechnung (`billing_root_id`). Beide Abläufe bleiben verwendbar. Ein Rechnungstitel ist optional; die Kundenverknüpfung muss übereinstimmen.

Bei Anzahlungsrechnungen sind Leistungsdatum bzw. Leistungszeitraum ausdrücklich voraussichtlich. Die Datumsfelder geben den geplanten Ausführungstag oder das geplante Zeitfenster an, keine Zahlungsfrist. Für einen einzelnen Tag bleibt das Bis-Datum leer; ein Zeitraum muss nach dem Von-Datum enden.

Jeder Abschlag fordert nur den neuen Betrag an, ohne kumulative Abrechnung. Die Schlussrechnung enthält alle Auftragsleistungen zum Gesamtpreis. `deducted_payments` speichert serverseitig Rechnungs-ID/-nummer, Rechnungsdatum, Zahlungsdatum und Betrag der erhaltenen Zahlungen. Die Festschreibung prüft unter der vorhandenen Workspace-Sperre erneut. Die Aufstellung bleibt anschließend unveränderlich. Es gibt höchstens eine aktive Schlussrechnung je Auftrag.

`total` bleibt der Gesamtpreis. `payment_total` ist der Gesamtpreis abzüglich angerechneter Zahlungen. Buchhaltung und Rechnungsumsatzhinweis verwenden den Zahlbetrag, damit frühere Rechnungen nicht doppelt zählen. Die tatsächliche EÜR basiert weiterhin auf den einzelnen Zahlungseingängen. Der Datenexport enthält Rechnungsart, Auftragsbezug, Aufstellung und Zahlbetrag. Der Export enthält außerdem `angebote-und-auftraege.json` sowie `rechnungs-auftragsbezug.json` mit Auftragsmomentaufnahmen und Berechnungsangaben. Die Workspace-Löschung entfernt Rechnungen, Aufträge und Angebote zusammen.

XRechnung: Vorschüsse verwenden Dokumenttyp 386; Schlussrechnungen 380. Die Anrechnung steht in `TotalPrepaidAmount`, der Rest in `DuePayableAmount`; eine Notiz nennt die einzelnen Rechnungen und Zahlungen. Stornos übernehmen die ursprüngliche Aufstellung mit umgekehrtem Vorzeichen, sodass nur der ursprüngliche Zahlbetrag aufgehoben wird.

## Grenzen und Korrekturen

Alle aktiven Teilrechnungen müssen vor der Schlussrechnung vollständig bezahlt und in der App zugeordnet sein. Unbezahlte Teilrechnungen sind vorher zu bezahlen oder zu stornieren. Teilzahlungen innerhalb einer einzelnen Rechnung, Überzahlungen, Fremdwährungen, Steuerwechsel und Rechnungen mit Umsatzsteuerausweis sind in diesem Ablauf nicht unterstützt. Enthält eine Zahlung Rückzahlungen, ist die Teilrechnung vor der Schlussrechnung zu stornieren und bei Bedarf neu zu erstellen. Zahlungen bleiben dabei als Buchhaltungsnachweise erhalten.

Nach der Schlussrechnung sind neue Abschläge sowie Änderungen, Löschungen und Rückzahlungen angerechneter Zahlungen gesperrt. Zuerst die Schlussrechnung stornieren. Der Storno selbst löscht oder erstattet keine Zahlung. Bei einer Korrektur bleibt der ursprüngliche Auftragsbezug erhalten.

## Amtliche Grundlagen

- [§ 632a BGB](https://www.gesetze-im-internet.de/bgb/__632a.html): Abschlagszahlungen bei Werkverträgen.
- [§ 14 Abs. 5 UStG](https://www.gesetze-im-internet.de/ustg_1980/__14.html): Vorauszahlungen und Anrechnung in der Endrechnung; Steuerausweis ist von Kleinunternehmerfällen zu unterscheiden.
- [UStAE 14.8](https://ao.bundesfinanzministerium.de/usth/2024/A-Umsatzsteuergesetz/IV-Steuer-und-Vorsteuer/Paragraf-14/inhalt.html): Rechnungen über Vorauszahlungen und Endrechnungen.
- [UNECE UNTDID 1001](https://unece.org/fileadmin/DAM/trade/untdid/d97a/uncl/uncl1001.htm): Dokumenttyp 386 (Prepayment invoice).

## Rechnungsart in der Nummer

Der Platzhalter `[Rechnungsart]` (bisher `[Rechnungstyp]`, weiterhin unterstützt) ergibt `RE` (Rechnung), `ANZ` (Anzahlung), `ABS` (Abschlag), `SR` (Schlussrechnung), `ST` (Storno), `AN` (Angebot) und `AU` (Auftrag). Neue Standardformate verwenden `[Rechnungsart]-[Jahr]-[Fortlaufendenummer]`; bestehende Vorgaben, Entwürfe und festgeschriebene Nummern bleiben unverändert. Der Jahreszähler läuft über die Typen hinweg weiter. Bei einem Storno wird das ursprüngliche Format beibehalten, wenn es den Platzhalter enthält. Andernfalls gilt weiterhin `ST-[Jahr]-[Fortlaufendenummer]`.

Angebote und Aufträge verwenden dieselbe Nummernanzeige, dasselbe Format-Popup und denselben Formatierungsservice wie Rechnungen. Ihre Formate werden je Dokument in `SalesDocument.data` gespeichert. AN- und AU-Jahreszähler bleiben getrennt; die Vorschau reserviert keine Nummer. Beim Speichern werden Zähler und Eindeutigkeit unter der Workspace-Sperre erneut geprüft. Bestehende Nummern bleiben bei normalen Inhalts- oder Datumsänderungen erhalten; eine ausdrücklich geänderte Format- oder Zählervorgabe vergibt eine neue freie Nummer. Die Rechnungsnummernvorgabe wird dabei nicht verändert.
