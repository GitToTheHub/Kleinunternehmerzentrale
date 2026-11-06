require "csv"

class BookkeepingReport
  attr_reader :entries, :year, :assets, :adjustments, :imports, :expense_policy

  def initialize(entries, year, assets: BusinessAsset.none, adjustments: EuerAdjustment.none, imports: BookkeepingImport.none, statement: nil, expense_policy: nil)
    @statement = statement
    @expense_policy = expense_policy
    @year = year
    @entries = entries.in_year(year).includes(:invoice).order(:paid_on, :id)
    @cash_entries = entries.where(paid_on: Date.new(year, 1, 1)..Date.new(year, 12, 31))
    @assets = assets.includes(:asset_depreciations, :asset_private_uses).order(:acquired_on, :id).to_a
    @adjustments = adjustments.where(year: year).order(:id).to_a
    @imports = imports.respond_to?(:where) ? imports.where(year: year).order(:id).to_a : Array(imports).select { |item| item.year == year }
  end

  def totals
    @totals ||= BookkeepingEntry::KINDS.keys.index_with do |kind|
      entries.where(kind: kind).sum { |entry| entry.signed_amount }
    end
  end

  def field_totals
    @field_totals ||= home_office_allowance.apply(allowance.apply)
  end

  def allowance = @allowance ||= EuerProfessionAllowance.new(self, expense_policy)
  def home_office_allowance = @home_office_allowance ||= EuerHomeOfficeAllowance.new(self, expense_policy)

  def actual_field_totals
    @actual_field_totals ||= begin
      amounts = EuerFields::DEFINITIONS.keys.index_with { 0.to_d }
      entries.each do |entry|
        category = entry.effective_category
        next if category.blank?

        base = entry.kind == "expense" ? entry.deductible_amount : entry.tax_base
        amounts[category] += base
        if (disallowed = BookkeepingEntry::DISALLOWED[category])
          amounts[disallowed] += entry.business_tax_base - base
        end
        amounts[entry.kind == "expense" ? "input_vat" : "vat_collected"] += entry.business_vat
      end
      @cash_entries.each do |entry|
        case entry.kind
        when "deposit", "noncash_deposit"
          amounts["deposits"] += entry.signed_amount
        when "withdrawal", "noncash_withdrawal"
          amounts["withdrawals"] += entry.signed_amount
        when "income"
          amounts["withdrawals"] += entry.income_private_withdrawal
        when "expense"
          amounts["deposits"] += entry.business_amount if entry.payment_account == "private"
          amounts["withdrawals"] += entry.private_amount if entry.payment_account == "business"
        end
      end
      assets.each do |asset|
        schedule = asset.schedule(year)
        amounts[asset.depreciation_method == "gwg" ? "expense_gwg" : asset.depreciation_field] += schedule[:ordinary]
        amounts["afa_special"] += schedule[:special]
        amounts["asset_residual"] += schedule[:residual]
        if (private_use = asset.private_use_for(year))
          amounts[private_use.field_key] += private_use.amount
          amounts["withdrawals"] += private_use.amount
        end
        if asset.origin == "contribution" && asset.acquired_on.year == year
          amounts["deposits"] += asset.cost
        elsif asset.origin == "purchase" && asset.paid_on&.year == year
          amounts["input_vat"] += asset.input_vat
          amounts["deposits"] += asset.cost + asset.input_vat if asset.payment_account == "private"
        end
        if asset.disposal_kind == "withdrawal" && asset.disposed_on&.year == year
          amounts["asset_income"] += asset.withdrawal_value
          amounts["vat_collected"] += asset.withdrawal_vat
          amounts["withdrawals"] += asset.withdrawal_value + asset.withdrawal_vat
        end
      end
      adjustments.each { |adjustment| amounts[adjustment.field_key] += adjustment.amount }
      imports.each { |import| import.field_amounts.each { |key, amount| amounts[key] += amount } }
      amounts
    end
  end

  def automatic_money_movements(kind)
    @cash_entries.filter_map do |entry|
      amount = if kind == "deposit" && entry.kind == "expense" && entry.payment_account == "private"
        entry.business_amount
      elsif kind == "withdrawal" && entry.kind == "income"
        entry.income_private_withdrawal
      elsif kind == "withdrawal" && entry.kind == "expense" && entry.payment_account == "business"
        entry.private_amount
      end
      { source: entry, date: entry.paid_on, description: entry.description, amount: amount } if amount && !amount.zero?
    end + (kind == "deposit" ? assets.filter_map do |asset|
      if asset.origin == "purchase" && asset.payment_account == "private" && asset.paid_on&.year == year
        { source: asset, date: asset.paid_on, description: asset.name, amount: asset.cost + asset.input_vat }
      end
    end : [])
  end

  def display_fields
    fields = EuerFields.supported?(year) ? EuerFields.fields_for(year) : EuerFields::DEFINITIONS.values
    fields.select do |field|
      EuerFields.small_business?(field.key) || !field_totals.fetch(field.key).zero?
    end
  end

  def legacy_tax_data?
    entries.any? { |entry| !EuerFields.small_business?(entry.effective_category) || entry.vat_amount.positive? } ||
      assets.any? { |asset| asset.input_vat.positive? || asset.withdrawal_vat.positive? } ||
      adjustments.any? { |item| !EuerFields.small_business?(item.field_key) }
  end

  def details
    imports.reduce({}) { |values, item| values.merge(item.details) }.merge(@statement&.details || {})
  end

  def detail_value(key)
    value = details[key]
    type = EuerForm::DETAILS.fetch(key).last
    type.is_a?(Hash) ? type[value] : value
  end

  def sum_effect(effect)
    EuerFields::DEFINITIONS.values.select { |field| field.effect == effect }.sum { |field| field_totals.fetch(field.key) }
  end

  def income = sum_effect(:income)
  def expenses = sum_effect(:expense) - sum_effect(:expense_reduction)
  def surplus = income - expenses + sum_effect(:profit_plus) - sum_effect(:profit_minus)
  def deposits = field_totals.fetch("deposits")
  def withdrawals = field_totals.fetch("withdrawals")
  def aveuer_rows = EuerAssetReport.new(self).rows

  def asset_rows
    @asset_rows ||= assets.filter_map do |asset|
      next if asset.acquired_on.year > year || (asset.tax_disposal_date && asset.tax_disposal_date.year < year)

      [ asset, asset.schedule(year) ]
    end
  end

  def warnings
    messages = []
    if home_office_allowance.elected? && !home_office_allowance.applicable?
      messages << "Die automatische Pauschale zuhause wird nicht angewendet: #{home_office_allowance.errors.join(' ')} Prüfe den Ansatz vor der Übertragung."
    end
    if allowance.elected? && !allowance.applicable?
      messages << "Die gewählte Betriebsausgabenpauschale wird nicht angewendet: #{allowance.errors.join(' ')} Die Übersicht verwendet vorläufig die tatsächlichen Ausgaben. Prüfe die Ausgabenmethode vor der Übertragung."
    end
    messages << EuerTaxRules.warning(year) unless EuerTaxRules.checked?(year)
    if assets.any? { |asset| asset.depreciation_method == "gwg" && asset.acquired_on.year <= year && !EuerTaxRules.checked?(asset.acquired_on.year) }
      messages << "Bei mindestens einem GWG ist die Grenze für das Anschaffungsjahr noch nicht jahresbezogen geprüft. Prüfe den Sofortabzug anhand der damaligen Regeln."
    end
    if EuerPreparationCheck.new(self).noncalendar_period?
      messages << EuerPreparationCheck::CALENDAR_WARNING
    end
    { "income_small_details" => "income_small", "property_repairs_details" => "expense_property" }.each do |part, total|
      if field_totals[part].negative? || (field_totals[part].positive? && field_totals[part] > field_totals[total])
        messages << "Die Davon-Angabe #{EuerFields::DEFINITIONS.fetch(part).label} überschreitet den zugehörigen Gesamtbetrag oder ist negativ. Prüfe die EÜR-Ergänzungen."
      end
    end
    if imports.any?(&:asset_amounts?)
      messages << "Übernommene Abschreibungen und Restbuchwerte enthalten keine Anlagegüter oder AVEÜR-Buchwerte. Prüfe die Abschreibung für den restlichen Jahreszeitraum. Für ein vollständiges Anlageverzeichnis übernimm die Summen ohne Anlagepositionen und erfasse die Anlagegüter samt Abschreibungshistorie separat."
    end
    if assets.any? { |asset| (asset.business_use_percent < 100 || asset.private_use_records.any? { |usage| usage.business_percent < 100 }) && !asset.private_use_for(year) && asset.acquired_on.year <= year && (!asset.disposed_on || asset.disposed_on.year >= year) }
      messages << "Bei mindestens einem gemischt genutzten Anlagegut ist der Nutzungsanteil nur dokumentiert. Ergänze die Jahresnutzung direkt beim Anlagegut. Bereits separat gebuchte Nutzungsentnahmen vorher prüfen, damit sie nicht doppelt zählen."
    end
    if assets.any? { |asset| asset.private_use_for(year)&.amount.to_d.positive? } && entries.any? { |entry| entry.kind == "noncash_withdrawal" }
      messages << "Es gibt private Nutzungswerte bei Anlagegütern und separat erfasste Sach- oder Nutzungsentnahmen. Prüfe, ob frühere manuelle Nutzungsentnahmen bereits dieselben Anlagegüter betreffen; deren Beträge dürfen nur einmal enthalten sein."
    end
    if legacy_tax_data?
      messages << "Es sind ältere Angaben zur Regelbesteuerung oder Steueraufteilung vorhanden. Sie bleiben in den Summen und im Export berücksichtigt. Prüfe und korrigiere diese Angaben für deine Kleinunternehmer-EÜR."
    end
    messages << "Für #{year} ist keine amtlich geprüfte Feldzuordnung hinterlegt. Die Übersicht zeigt Beträge ohne Zeilen und Kennziffern." unless EuerFields.supported?(year)
    if entries.any? { |entry| %w[income expense].include?(entry.kind) && entry.category.blank? }
      messages << "Ältere Buchungen verwenden Standardkategorien. Prüfe ihre steuerliche Zuordnung, insbesondere die Einnahmen als Kleinunternehmer."
    end
    if field_totals["expense_interest"] > EuerTaxRules.for(year).interest_threshold
      messages << "Die übrigen Schuldzinsen übersteigen 2.050 Euro. Prüfe die Anlage SZ und erfasse den ermittelten Hinzurechnungsbetrag als steuerliche Ergänzung."
    end
    if assets.any? { |asset| asset.depreciation_method == "manual" && asset.acquired_on.year <= year && (!asset.disposed_on || asset.disposed_on.year >= year) && asset.schedule(year)[:opening] + asset.schedule(year)[:additions] > 0 && asset.depreciation_records.none? { |record| record.year == year } }
      messages << "Bei mindestens einem Anlagegut mit manueller Abschreibung fehlt der Jahresbetrag. Ergänze ihn im Anlagegut, auch wenn die Abschreibung null beträgt."
    end
    messages
  end

  def csv
    "\uFEFF" + CSV.generate(col_sep: ";") do |out|
      out << [ "EÜR #{year}", "Übertragungshilfe; keine ELSTER-Importdatei" ]
      if home_office_allowance.applicable?
        out << [ "Pauschale zuhause", EuerHomeOfficeAllowance::METHODS.fetch(expense_policy.home_office_method), "Tage", expense_policy.home_days, "Monate", expense_policy.home_months, "Betrag EUR", money(home_office_allowance.amount), "Grundlage", safe(expense_policy.home_basis) ]
      end
      if allowance.applicable?
        out << [ "Ausgabenmethode", EuerProfessionAllowance::METHODS.fetch(expense_policy.deduction_method), "Maßgebliche Einnahmen EUR", money(allowance.revenue), "Pauschale EUR", money(allowance.amount) ]
        out << [ "Hinweis", "Die Betriebsausgabenpauschale ersetzt die tatsächlichen Ausgaben einschließlich AfA in der EÜR. Zahlungen und Anlagebuchwerte bleiben dokumentiert." ]
        if expense_policy.deduction_method == "daycare"
          out << [ "Kindertagespflege", "Kürzel", "Erster Monat", "Letzter Monat", "Platzart", "Wochenstunden", "Belegte Tage je Monat", "Tagesstunden" ]
          expense_policy.daycare_rows.each do |row|
            out << [ "Betreuungszeitraum", safe(row["label"]), row["start_month"], row["end_month"], row["kind"], row["weekly_hours"], row["occupied_days"], row["daily_hours"] ]
          end
        end
      end
      out << [ "Zeile", "Bereich/Kennziffer", "Kategorie", "Betrag EUR" ]
      display_fields.each do |field|
        out << [ EuerFields.line(field.key, year), EuerFields.supported?(year) && field.number ? "#{field.section}/#{field.number}" : nil, field.label, money(field_totals.fetch(field.key)) ]
      end
      out << [ nil, nil, "Summe Betriebseinnahmen", money(income) ]
      out << [ nil, nil, "Summe abziehbare Betriebsausgaben", money(expenses) ]
      out << [ EuerFields.supported?(year) ? (year == 2025 ? 97 : 98) : nil, EuerFields.supported?(year) ? "25/219" : nil, "Steuerlicher Gewinn / Verlust aus den erfassten Angaben", money(surplus) ]
      if EuerFields.supported?(year)
        out << []
        out << [ "Vollständige Anlage EÜR", "Zeile", "Position", "Amtliche Bezeichnung", "Wert" ]
        EuerForm.rows(year).each do |row|
          value = row.kind == :detail ? safe(detail_value(row.key)) : money(EuerForm.amount(row.key, self))
          out << [ year, row.line, row.number, row.label, value ]
        end
      end
      out << []
      separate_tax = legacy_tax_data?
      out << ([ "Datum", "Steuerjahr", "Art", "Kategorie", "Beschreibung", "Belegnummer", "Gesamtbetrag EUR" ] + (separate_tax ? [ "Steueranteil EUR" ] : []) + [ "Abziehbar %", "Konto", "Erstattung / Rückzahlung", "Betrieblich %", "Betrieblicher Betrag EUR", "Nutzungsbegründung", "Bargeldverwendung", "Bargeld privat EUR" ])
      entries.each do |entry|
        out << [ entry.paid_on, entry.effective_year, BookkeepingEntry::KINDS.fetch(entry.kind), label(entry.effective_category), safe(entry.description), safe(entry.reference), money(entry.signed_amount), *(separate_tax ? [ money(entry.signed_vat) ] : []), entry.kind == "expense" ? money(entry.deductible_share) : nil, entry.payment_account, entry.reversal? ? "Ja" : "Nein", money(entry.business_percent), money(entry.business_amount), safe(entry.usage_notes), entry.cash_usage, money(entry.cash_private_amount) ]
      end
      out << []
      out << [ "Anlagegut", "Anschaffung / Einlage", "Methode", "Zugang EUR", "Buchwert Jahresbeginn EUR", "AfA EUR", "Sonder-AfA EUR", "Restbuchwert Abgang EUR", "Buchwert Jahresende EUR", "Betriebliche Nutzung % (Dokumentation)", "Nutzungsgrundlage" ]
      asset_rows.each do |asset, schedule|
        out << [ safe(asset.name), asset.acquired_on, BusinessAsset::METHODS.fetch(asset.depreciation_method), *%i[additions opening ordinary special residual closing].map { |key| money(schedule.fetch(key)) }, money(asset.business_use_percent), safe(asset.usage_basis) ]
      end
      out << []
      out << [ "Private Nutzung Anlagegut", "Jahr", "Betrieblich %", "Berechnung", "Privatnutzungswert EUR", "Grundlage" ]
      assets.each do |asset|
        next unless (usage = asset.private_use_for(year))

        out << [ safe(asset.name), year, money(usage.business_percent), AssetPrivateUse::MODES.fetch(usage.calculation_mode), money(usage.amount), safe(usage.basis) ]
      end
      out << []
      out << [ "AVEÜR-Gruppe", "Zeile", "Kennziffer", "Position", "Betrag EUR" ]
      aveuer_rows.each { |row| out << [ row[:group], row[:line], row[:number], row[:label], money(row[:amount]) ] }
      out << []
      out << [ "Steuerliche Ergänzung", "Begründung", "Betrag EUR" ]
      adjustments.each { |item| out << [ label(item.field_key), safe(item.description), money(item.amount) ] }
      out << []
      out << [ "Übernommene EÜR-Summen", "Quelle", "Zeitraum bis", "Position", "Betrag EUR", "Anlagegüter separat" ]
      imports.each do |import|
        import.field_amounts.each { |key, amount| out << [ import.year, safe(import.source), import.covered_through, label(key), money(amount), import.assets_managed_separately? ? "Ja" : "Nein" ] }
        out << [ "Hinweise zur PDF-Übernahme", safe(import.notes) ] if import.notes.present?
      end
      check = EuerPreparationCheck.new(self)
      if check.missing_keys.any?
        out << [ "Betriebsangaben prüfen", check.missing_keys.map { |key| EuerForm::DETAILS.fetch(key)[1] }.join("; ") ]
      end
      check.warnings.each { |message| out << [ "Prüfhinweis", safe(message) ] }
    end
  end

  private

  def money(value) = value.to_d.to_s("F").tr(".", ",")
  def label(key) = EuerFields::DEFINITIONS[key]&.label

  def safe(value)
    value.to_s.match?(/\A[=+\-@\t\r\n]/) ? "'#{value}" : value
  end
end
