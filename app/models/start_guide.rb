# Die Schritte für den Start als Kleinunternehmer. Es wird immer nur der nächste offene Schritt groß gezeigt.
class StartGuide
  Step = Data.define(:key, :title, :text, :link_text, :link_path)

  STEPS = [
    Step.new("anmelden", "Tätigkeit anmelden",
      "Du meldest deine Tätigkeit bei der Gemeinde (Gewerbe) oder beim Finanzamt (freier Beruf) an. Das geht oft online und dauert nicht lange.",
      "So geht die Anmeldung", :gewerbeanmeldung_path),
    Step.new("finanzamt", "Fragebogen vom Finanzamt ausfüllen",
      "Nach der Anmeldung bekommst du vom Finanzamt den „Fragebogen zur steuerlichen Erfassung“. Dort sagst du, dass du Kleinunternehmer sein möchtest. Danach erhältst du deine Steuernummer.",
      nil, nil),
    Step.new("rechnung", "Erste Rechnung schreiben",
      "Mit deiner Steuernummer kannst du die erste Rechnung schreiben. Die App fragt dich Schritt für Schritt nach allem, was draufstehen muss.",
      "Rechnung erstellen", :new_invoice_path),
    Step.new("aufschreiben", "Einnahmen und Ausgaben aufschreiben",
      "Halte jede Zahlung fest, die du bekommst oder für dein Geschäft ausgibst, und hebe die Belege auf. Am Jahresende stellst du beides in einer Tabelle gegenüber (EÜR). Mehr brauchst du nicht.",
      nil, nil),
    Step.new("aufbewahren", "Rechnungen sicher aufbewahren",
      "Speichere jede Rechnung als PDF auf deinem Gerät. Rechnungen musst du 8 Jahre lang unverändert aufbewahren.",
      nil, nil)
  ].freeze

  def self.keys = STEPS.map(&:key)

  def initialize(workspace)
    @workspace = workspace
  end

  def done?(step)
    return @workspace&.invoices&.exists? || false if step.key == "rechnung"

    @workspace&.completed_steps&.include?(step.key) || false
  end

  def steps = STEPS

  def current = STEPS.find { |step| !done?(step) }

  def finished? = current.nil?

  def position(step) = STEPS.index(step) + 1
end
