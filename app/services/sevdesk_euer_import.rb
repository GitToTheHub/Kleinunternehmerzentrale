require "tempfile"
require "timeout"

# Reads text-based sevdesk EÜR reports locally. PDF contents are data, never commands.
class SevdeskEuerImport
  MAX_BYTES = 10.megabytes
  MAX_TEXT = 2.megabytes
  Result = Data.define(:year, :covered_through, :amounts, :notes)
  AMOUNT_ROW = /\s(\d{1,3})\s+(\d{2,3})\s+(-?(?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})\s*€\s*\z/
  TOTALS = { "159" => "income_total", "199" => "expenses_total", "219" => "profit_total", "290" => "corrected_profit", "293" => "profit_before_interest", "190" => "reserve_creation_total", "124" => "reserve_release_total" }.freeze

  def self.pdf(upload)
    raise EuerTotalsImport::InvalidFile, "Die PDF-Datei darf höchstens 10 MB groß sein." if upload.size > MAX_BYTES
    raise EuerTotalsImport::InvalidFile, "Wähle eine gültige PDF-Datei aus." unless File.binread(upload.tempfile.path, 5) == "%PDF-"

    Tempfile.create([ "sevdesk-euer", ".txt" ]) do |output|
      pid = Process.spawn("pdftotext", "-layout", "-enc", "UTF-8", "-f", "1", "-l", "20", upload.tempfile.path, output.path,
        out: File::NULL, err: File::NULL, pgroup: true, rlimit_cpu: 10, rlimit_fsize: MAX_TEXT)
      begin
        _, status = Timeout.timeout(15) { Process.wait2(pid) }
      rescue Timeout::Error
        Process.kill("KILL", -pid) rescue Errno::ESRCH
        Process.wait(pid) rescue Errno::ECHILD
        raise EuerTotalsImport::InvalidFile, "Die PDF konnte nicht rechtzeitig gelesen werden. Verwende eine kleinere, textbasierte sevdesk-EÜR."
      end
      raise EuerTotalsImport::InvalidFile, "Die PDF konnte nicht gelesen werden. Sie muss unverschlüsselt sein und auswählbaren Text enthalten." unless status.success?

      text(File.read(output.path, encoding: "UTF-8"))
    end
  rescue Errno::ENOENT
    raise EuerTotalsImport::InvalidFile, "Der PDF-Import ist auf diesem Server noch nicht eingerichtet. Bitte verwende vorerst CSV oder die direkte Eingabe."
  end

  def self.text(content)
    fail_import("Die PDF enthält keinen lesbaren EÜR-Text. Gescannte Dokumente werden nicht unterstützt.") unless content.valid_encoding? && content.include?("Einnahmenüberschussrechnung")
    pages = content.scan(/Seite:\s*(\d+)\s*\/\s*(\d+)/).map { |page, count| [ page.to_i, count.to_i ] }
    fail_import("Die PDF enthält zu viele Seiten.") if pages.any? { |_, count| count > 20 }
    fail_import("Die PDF-Seiten sind unvollständig oder mehrfach vorhanden.") unless pages.any? && pages.map(&:last).uniq.one? && pages.map(&:first).sort == (1..pages.first.last).to_a
    periods = content.scan(/Zeitraum:\s*(\d{2}\.\d{2}\.\d{4})\s*-\s*(\d{2}\.\d{2}\.\d{4})/).uniq
    stands = content.scan(/Stand:\s*(\d{2}\.\d{2}\.\d{4})/).flatten.uniq
    fail_import("Berichtszeitraum oder Stand der sevdesk-EÜR sind nicht eindeutig erkennbar.") unless periods.one? && stands.one?
    start_date, end_date = periods.sole.map { |date| Date.strptime(date, "%d.%m.%Y") }
    as_of = Date.strptime(stands.sole, "%d.%m.%Y")
    year = start_date.year
    fail_import("Die PDF muss ein unterstütztes, kalendergleiches EÜR-Jahr enthalten.") unless EuerFields.supported?(year) && start_date == Date.new(year, 1, 1) && end_date == Date.new(year, 12, 31)
    fail_import("Der Stand der PDF liegt vor dem Berichtsjahr.") if as_of < start_date

    section = nil
    amounts = {}
    totals = {}
    mismatched_lines = false
    line_years = []
    content.each_line do |line|
      section = "20" if line.match?(/^\s*1\.\s*Betriebseinnahmen/)
      section = "25" if line.match?(/^\s*[23]\.\s*(Betriebsausgaben|Ermittlung des Gewinns)/)
      section = "27" if line.match?(/^\s*4\.\s*Ergänzende Angaben/)
      section = "29" if line.match?(/^\s*\d\.\s*Zusätzliche Angaben bei Einzelunternehmen/)
      next unless line.match?(/€\s*\z/)

      match = line.match(AMOUNT_ROW)
      fail_import("Eine Betragszeile konnte nicht eindeutig gelesen werden. Es wurden keine Werte übernommen.") unless match && section
      printed_line, position, raw_amount = match.captures
      amount = EuerTotalsImport.parse_amount(raw_amount)
      candidates = EuerFields::DEFINITIONS.values.select { |field| field.section == section && field.number == position }
      if candidates.one?
        field = candidates.sole
        fail_import("Position #{position} passt nicht zum erkannten EÜR-Jahr.") unless EuerFields.line(field.key, year)
        known_lines = EuerFields::SOURCES.keys.filter_map { |source_year| EuerFields.line(field.key, source_year) }
        fail_import("Zeile #{printed_line} und Position #{position} passen nicht zusammen.") unless known_lines.include?(printed_line.to_i)
        fail_import("Position #{position} ist mehrfach enthalten. Bitte prüfe die PDF.") if amounts.key?(field.key)
        mismatched_lines ||= EuerFields.line(field.key, year) != printed_line.to_i
        line_years |= EuerFields::SOURCES.keys.select { |source_year| source_year != year && EuerFields.line(field.key, source_year) == printed_line.to_i }
        amounts[field.key] = amount
      elsif TOTALS.key?(position)
        key = TOTALS.fetch(position)
        permitted = EuerFields::SOURCES.keys.flat_map { |source_year| EuerForm.rows(source_year).select { |row| [ key, ({ "income_total" => "income_repeat", "expenses_total" => "expenses_repeat" }[key]) ].compact.include?(row.key) }.map(&:line) }
        sections = %w[190 124].include?(position) ? %w[27] : (position == "159" ? %w[20 25] : %w[25])
        fail_import("Eine Summenzeile ist nicht eindeutig zuzuordnen.") unless permitted.include?(printed_line.to_i) && sections.include?(section)
        fail_import("Wiederholte Summen stimmen nicht überein.") if totals.key?(key) && totals[key] != amount
        totals[key] = amount
      else
        fail_import("Die Position #{position} wird in diesem PDF-Aufbau nicht sicher erkannt. Es wurden keine Werte übernommen.")
      end
    end
    fail_import("Einnahmen-, Ausgaben- oder Gewinnsumme fehlt. Bitte lade eine vollständige sevdesk-EÜR hoch.") unless %w[income_total expenses_total profit_total].all? { |key| totals.key?(key) }
    fail_import("In der PDF wurden keine EÜR-Positionen gefunden.") if amounts.empty?
    values = amounts.reject { |_, amount| amount.to_d.zero? }
    report = BookkeepingReport.new(BookkeepingEntry.none, year, imports: [ BookkeepingImport.new(year: year, amounts: values) ])
    totals.each do |key, value|
      fail_import("Die gelesenen Einzelpositionen stimmen nicht mit den PDF-Summen überein. Bitte prüfe den Bericht; es wurden keine Werte übernommen.") unless EuerForm.amount(key, report) == value.to_d
    end
    notes = [ "Aus einer textbasierten sevdesk-EÜR gelesen. Berichtszeitraum: #{start_date.strftime('%d.%m.%Y')} – #{end_date.strftime('%d.%m.%Y')}. Stand: #{as_of.strftime('%d.%m.%Y')}.",
      "Der vorgeschlagene Stichtag stammt aus dem PDF-Stand, höchstens dem Ende des Berichtsjahrs. Der Stand allein beweist nicht, bis zu welchem Zahlungsdatum alle Buchungen enthalten sind. Prüfe den Stichtag vor der Übernahme." ]
    notes << "Die PDF verwendet teilweise Zeilennummern eines anderen Formularjahrs (erkannt: #{line_years.sort.join(", ")}). Die Zuordnung erfolgte nach EÜR-Bereich und Positionsnummer; angezeigt werden die amtlichen Zeilen für #{year}." if mismatched_lines
    Result.new(year, [ as_of, end_date ].min, values, notes.join("\n\n"))
  rescue Date::Error
    fail_import("Der Berichtszeitraum enthält ein ungültiges Datum.")
  end

  def self.fail_import(message)
    raise EuerTotalsImport::InvalidFile, message
  end
  private_class_method :fail_import
end
