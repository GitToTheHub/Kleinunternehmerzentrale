# Prüft den Umsatz gegen die Grenzen der Kleinunternehmerregelung (§ 19 UStG):
# höchstens 25.000 € im Vorjahr und höchstens 100.000 € im laufenden Jahr.
class RevenueLimits
  PREVIOUS_YEAR_LIMIT = 25_000
  CURRENT_YEAR_LIMIT = 100_000
  NOTICE_FROM = 20_000
  Notice = Data.define(:level, :title, :text)

  def initialize(workspace, today: Date.current)
    @workspace = workspace
    @today = today
  end

  def revenue(year)
    return 0 unless @workspace

    @workspace.invoices.where(issued_on: Date.new(year, 1, 1)..Date.new(year, 12, 31), tax_mode: "small_business")
              .includes(:invoice_lines).sum(&:total)
  end

  def current_revenue = revenue(@today.year)

  # Gibt nur dann einen Hinweis zurück, wenn er für die Nutzerin oder den Nutzer gerade relevant ist.
  def notice
    current = current_revenue
    previous = revenue(@today.year - 1)

    if current > CURRENT_YEAR_LIMIT
      Notice.new(:alert, "Du hast die Grenze von 100.000 € überschritten",
        "Ab dem Umsatz, der die 100.000 € übersteigt, musst du Umsatzsteuer ausweisen. Sprich bitte zeitnah mit dem Finanzamt oder einer Steuerberatung. Dort kannst du auch einfach nachfragen, wie es jetzt weitergeht.")
    elsif previous > PREVIOUS_YEAR_LIMIT
      Notice.new(:alert, "Dein Umsatz im letzten Jahr lag über 25.000 €",
        "Deshalb gilt die Kleinunternehmerregelung in diesem Jahr nicht mehr. Wähle bei neuen Rechnungen „Regelbesteuerung“ und frage das Finanzamt, was du jetzt tun musst.")
    elsif current > PREVIOUS_YEAR_LIMIT
      Notice.new(:warning, "Du bist in diesem Jahr über 25.000 € Umsatz",
        "Das ist kein Problem: Bis 100.000 € bleibst du in diesem Jahr Kleinunternehmer. Aber im nächsten Jahr gilt die Regelung nicht mehr. Plane das schon jetzt ein.")
    elsif current >= NOTICE_FROM
      Notice.new(:info, "Du näherst dich der Grenze von 25.000 €",
        "Dieses Jahr hast du etwa #{format_euro(current)} Umsatz. Bleibt dein Umsatz im ganzen Jahr unter 25.000 €, kannst du Kleinunternehmer bleiben. Mehr kommt später, du musst jetzt nichts tun.")
    end
  end

  private

  def format_euro(value)
    ActiveSupport::NumberHelper.number_to_currency(value, unit: "€", format: "%n %u", locale: :de, precision: 0)
  end
end
