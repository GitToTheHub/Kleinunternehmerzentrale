# Zentrale Stelle für steuerliche Kennzahlen, damit sie jährlich an einer Stelle aktualisiert werden.
# Gegen die Gesetzestexte (gesetze-im-internet.de) geprüft: Oktober 2026.
module Steuerwerte
  STAND = "Oktober 2026"

  # § 19 Abs. 1 UStG
  KLEINUNTERNEHMER_VORJAHRESGRENZE = 25_000
  KLEINUNTERNEHMER_LAUFENDE_GRENZE = 100_000

  # § 11 Abs. 1 GewStG (natürliche Personen und Personengesellschaften)
  GEWERBESTEUER_FREIBETRAG = 24_500

  # § 3 Abs. 3 IHKG
  IHK_BEFREIUNG_GEWERBEERTRAG = 5_200
  IHK_BEFREIUNG_GRUENDER_GEWERBEERTRAG = 25_000

  # § 32a Abs. 1 EStG (Veranlagungszeitraum 2026)
  GRUNDFREIBETRAG_2026 = 12_348

  # Mindestbemessungsgrundlage für freiwillig Versicherte in der GKV (2026)
  GKV_MINDESTBEMESSUNGSGRUNDLAGE_2026 = 1_318.33

  # Beitragssätze IKK gesund plus (2026)
  IKK_GESUND_PLUS_ZUSATZBEITRAG_2026 = 3.39
  IKK_GESUND_PLUS_PFLEGE_KINDERLOS_2026 = 4.2
  IKK_GESUND_PLUS_PFLEGE_MIT_KIND_2026 = 3.6

  # Beispiel: Gebühr variiert je Gemeinde (Quelle: service.berlin.de)
  GEWERBEANMELDUNG_BERLIN = 26
  GEWERBEANMELDUNG_BERLIN_ONLINE = 15
end
