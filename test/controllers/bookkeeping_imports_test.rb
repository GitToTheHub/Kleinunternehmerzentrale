require "test_helper"

class BookkeepingImportsTest < ActionDispatch::IntegrationTest
  def import_params
    { year: 2026, covered_through: "2026-09-29", source: "sevdesk bis September",
      amounts: { income_small: "1.000,00", expense_meals: "70,00", meals_disallowed: "30,00", deposits: "200,00", withdrawals: "300,00" } }
  end

  def preview(**extra)
    post preview_bookkeeping_imports_url, params: { bookkeeping_import: import_params.merge(extra) }
    assert_response :success
    Nokogiri::HTML(response.body).at_css("input[name=token]")["value"]
  end

  def commit(token)
    post bookkeeping_imports_url, params: { token: token, confirmed: "1" }
  end

  test "import uses original form captions and year specific references" do
    get new_bookkeeping_import_url
    assert_response :success
    assert_select "label[for=import_amount_income_small]", /Betriebseinnahmen als umsatzsteuerlicher Kleinunternehmer/
    assert_select "label[for=import_amount_expense_it] [data-references]" do |nodes|
      assert_equal "Zeile 50", JSON.parse(nodes.first["data-references"])["2025"]
      assert_equal "Zeile 51", JSON.parse(nodes.first["data-references"])["2026"]
    end
    assert_select "label[for=import_amount_expense_meals]", /Bewirtungsaufwendungen – abziehbar/
    assert_select "label[for=import_amount_meals_disallowed]", /Bewirtungsaufwendungen – nicht abziehbar/
    preview(year: 2025, covered_through: "2025-12-31", amounts: { expense_it: "100,00" })
    assert_select "tr", /Zeile 50.*Laufende EDV-Kosten/
    assert_select "th", "EÜR-Bezeichnung"
    post preview_bookkeeping_imports_url, params: { bookkeeping_import: import_params.merge(year: 2024) }
    assert_response :unprocessable_entity
  end

  test "form references hide technical codes and disclose unsupported requested years" do
    get new_bookkeeping_import_url(year: 2025)
    assert_select "[data-bookkeeping-import-target=sourceNote]", "Formulargrundlage: amtliche Anlage EÜR 2025."
    assert_select "label[for=import_amount_income_small]" do |nodes|
      assert_includes nodes.first.text, "Zeile 12"
      assert_not_includes nodes.first.text, "111"
    end
    missing_year = EuerFields::SOURCES.keys.max + 1
    get new_bookkeeping_import_url(year: missing_year)
    assert_response :success
    assert_select ".flash-message--alert", /Für das angefragte Steuerjahr #{missing_year}/
    assert_select "#bookkeeping_import_year option[selected]", EuerFields::SOURCES.keys.max.to_s
    assert_select "[data-bookkeeping-import-target=sourceNote]", "Formulargrundlage: amtliche Anlage EÜR #{EuerFields::SOURCES.keys.max}."
    get new_euer_adjustment_url(year: missing_year)
    assert_response :success
    assert_select ".flash-message--alert", /diese Zuordnung gilt nicht für #{missing_year}/
    assert_select "[data-euer-position-target=sourceNote]", "Formulargrundlage: amtliche Anlage EÜR #{EuerFields::SOURCES.keys.max}."
    get prepare_euer_bookkeeping_entries_url(year: missing_year)
    assert_select ".form-note", /keine amtlich geprüften Formulardaten/
  end

  test "preview makes no records and import contributes exact totals without double private equity" do
    get new_bookkeeping_import_url
    assert_response :success
    token = nil
    assert_no_difference [ "BookkeepingImport.count", "BookkeepingEntry.count", "EuerAdjustment.count" ] do
      token = preview
    end
    assert_select "dd", "930,00 €"
    assert_difference "BookkeepingImport.count" do
      commit(token)
    end
    assert_response :redirect
    import = BookkeepingImport.order(:id).last
    get bookkeeping_entries_url(year: 2026)
    assert_select "dd strong", "930,00 €"
    assert_select "dd", "200,00 €"
    assert_select "dd", "300,00 €"
    post bookkeeping_entries_url, params: { bookkeeping_entry: { kind: "income", paid_on: "2026-09-30", amount: "100", description: "Neue Zahlung" } }
    assert_response :redirect
    get bookkeeping_entries_url(year: 2026)
    assert_select "dd strong", "1.030,00 €"
    get bookkeeping_entries_url(year: 2026, format: :csv)
    assert_includes response.body, "Übernommene EÜR-Summen"
    assert_includes response.body, "sevdesk bis September"
    get export_url
    names = []
    Zip::InputStream.open(StringIO.new(response.body)) do |zip|
      while (item = zip.get_next_entry)
        names << item.name
      end
    end
    assert_includes names, "euer-uebernahmen.csv"
    delete bookkeeping_import_url(import)
    assert_response :see_other
    assert_equal 1, import.workspace.bookkeeping_entries.count
    get bookkeeping_entries_url(year: 2026)
    assert_select "dd strong", "100,00 €"
  end

  test "commit is confirmed scoped signed and repeat safe" do
    token = preview
    post bookkeeping_imports_url, params: { token: token }
    assert_response :unprocessable_entity
    assert_equal 0, BookkeepingImport.count
    other = ActionDispatch::Integration::Session.new(Rails.application)
    other.post bookkeeping_imports_url, params: { token: token, confirmed: "1" }
    assert_equal 0, BookkeepingImport.count
    commit(token + "bad")
    assert_response :redirect
    assert_equal 0, BookkeepingImport.count
    commit(token)
    assert_equal 1, BookkeepingImport.count
    assert_no_difference "BookkeepingImport.count" do
      commit(token)
    end
    assert_response :unprocessable_entity
    other.get bookkeeping_import_url(BookkeepingImport.last)
    assert_equal 404, other.response.status
    other.delete bookkeeping_import_url(BookkeepingImport.last)
    assert_equal 404, other.response.status
  end

  test "overlapping records are checked both at preview and confirmation and later blocked" do
    token = preview
    attrs = { kind: "income", paid_on: "2026-09-29", amount: "50", description: "Schon erfasst" }
    post bookkeeping_entries_url, params: { bookkeeping_entry: attrs }
    assert_response :redirect
    commit(token)
    assert_response :unprocessable_entity
    assert_equal 0, BookkeepingImport.count
    post preview_bookkeeping_imports_url, params: { bookkeeping_import: import_params }
    assert_response :unprocessable_entity
    entry = BookkeepingEntry.order(:id).last
    delete bookkeeping_entry_url(entry)
    commit(preview)
    assert_no_difference "BookkeepingEntry.count" do
      post bookkeeping_entries_url, params: { bookkeeping_entry: attrs }
    end
    assert_response :unprocessable_entity
    post bookkeeping_entries_url, params: { bookkeeping_entry: attrs.merge(paid_on: "2026-09-30") }
    assert_response :redirect
  end

  test "invalid dates amounts and empty or DATEV files show actionable errors" do
    [ import_params.merge(covered_through: "2025-09-29"), import_params.merge(covered_through: Date.current + 1),
      import_params.merge(amounts: {}), import_params.merge(amounts: { income_small: "12,345" }) ].each do |attrs|
      post preview_bookkeeping_imports_url, params: { bookkeeping_import: attrs }
      assert_response :unprocessable_entity
    end
    post preview_bookkeeping_imports_url, params: { bookkeeping_import: import_params, input_mode: "csv" }
    assert_response :unprocessable_entity
    file = Tempfile.new([ "datev", ".csv" ])
    file.write("EXTF;700;21\nUmsatz;Soll/Haben-Kennzeichen\n")
    file.close
    post preview_bookkeeping_imports_url, params: { bookkeeping_import: import_params, input_mode: "csv", file: Rack::Test::UploadedFile.new(file.path, "text/csv") }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /DATEV-Buchungsstapel/
  ensure
    file&.unlink
  end

  test "asset deductions cannot be doubled and account erasure includes imports" do
    commit(preview(amounts: { afa_movable: "300,00" }))
    import = BookkeepingImport.last
    assert_equal 300, import.expenses
    asset = import.workspace.business_assets.new(name: "Alter Computer", acquired_on: "2025-01-01", cost: 1000,
      category: "office", origin: "purchase", depreciation_method: "linear", useful_life: 3)
    assert_not asset.valid?
    assert_match(/bereits Abschreibungen/, asset.errors.full_messages.join)
    get bookkeeping_entries_url(year: 2026)
    assert_select "[role=status]", /AVEÜR/
    workspace_id = import.workspace_id
    import.workspace.erase!
    assert_not BookkeepingImport.where(workspace_id: workspace_id).exists?
  end

  test "CSV upload template and expired previews work through HTTP" do
    get template_bookkeeping_imports_url
    assert_response :success
    assert_includes response.body, "Position;Betrag;Beschreibung"
    file = Tempfile.new([ "euer", ".csv" ])
    file.write("Position;Betrag\nincome_small;160,00\nexpense_phone;20,00\n")
    file.close
    post preview_bookkeeping_imports_url, params: { bookkeeping_import: import_params.except(:amounts), input_mode: "csv", file: Rack::Test::UploadedFile.new(file.path, "text/csv") }
    assert_response :success
    assert_select "dd strong", "140,00 €"
    token = Nokogiri::HTML(response.body).at_css("input[name=token]")["value"]
    travel 31.minutes do
      assert_no_difference "BookkeepingImport.count" do
        commit(token)
      end
      assert_response :redirect
    end
    commit(token)
    assert_response :redirect
    assert_equal "160.0", BookkeepingImport.last.amounts.fetch("income_small")
  ensure
    file&.unlink
  end

  test "private asset deposits cannot duplicate imported equity" do
    commit(preview(amounts: { income_small: "100", deposits: "200" }))
    import = BookkeepingImport.last
    asset = import.workspace.business_assets.new(name: "Privat bezahlter Computer", acquired_on: "2026-01-10", paid_on: "2026-01-10",
      cost: 500, category: "office", origin: "purchase", depreciation_method: "gwg", gwg_net_value: 500, payment_account: "private")
    assert_not asset.valid?
    assert_match(/zugehörige Einlagen/, asset.errors.full_messages.join)
    asset.paid_on = "2026-09-30"
    assert asset.valid?, asset.errors.full_messages.join
  end

  test "separate asset strategy excludes deductions but allows unrelated imported equity" do
    post preview_bookkeeping_imports_url, params: { bookkeeping_import: import_params.merge(assets_managed_separately: "1", amounts: { income_small: "100", afa_movable: "20" }) }
    assert_response :unprocessable_entity
    token = preview(assets_managed_separately: "1", amounts: { income_small: "100", deposits: "200" })
    commit(token)
    import = BookkeepingImport.last
    assert import.assets_managed_separately?
    asset = import.workspace.business_assets.create!(name: "Privat bezahlter Computer", acquired_on: "2026-01-10", paid_on: "2026-01-10",
      cost: 500, category: "office", origin: "purchase", depreciation_method: "gwg", gwg_net_value: 500, payment_account: "private")
    get bookkeeping_entries_url(year: 2026)
    assert_select "dd", "700,00 €"
    assert_select "dd strong", "-400,00 €"
    assert_equal 500, asset.schedule(2026)[:ordinary]
  end
  test "PDF import is previewed with checked amounts and a revisable signed cutoff" do
    parsed = SevdeskEuerImport.text(File.read(file_fixture("sevdesk_euer.txt")))
    original = SevdeskEuerImport.method(:pdf)
    SevdeskEuerImport.define_singleton_method(:pdf) { |_| parsed }
    begin
      assert_no_difference "BookkeepingImport.count" do
        post preview_bookkeeping_imports_url, params: { input_mode: "pdf", file: Rack::Test::UploadedFile.new(file_fixture("sevdesk_euer.txt"), "application/pdf"), bookkeeping_import: { source: "" } }
      end
    ensure
      SevdeskEuerImport.define_singleton_method(:pdf, original)
    end
    assert_response :success
    assert_select "dd strong", "880,00 €"
    assert_includes response.body, "Zeilennummern eines anderen Formularjahrs"
    token = Nokogiri::HTML(response.body).at_css("input[name=token]")["value"]
    post preview_bookkeeping_imports_url, params: { review_token: token, bookkeeping_import: { covered_through: "2026-09-28", source: "sevdesk geprüft", amounts: { income_small: "999999" }, notes: "Manipuliert" } }
    assert_response :success
    assert_select "dd strong", "880,00 €"
    token = Nokogiri::HTML(response.body).at_css("input[name=token]")["value"]
    commit(token)
    assert_response :redirect
    import = BookkeepingImport.last
    assert_equal Date.new(2026, 9, 28), import.covered_through
    assert_equal "1000.0", import.amounts["income_small"]
    assert_includes import.notes, "Zeilennummern eines anderen Formularjahrs"
    assert_not_includes import.notes, "Manipuliert"
    get new_bookkeeping_import_url
    assert_select "details", count: 0
    assert_select "[name^='bookkeeping_import[details]']", count: 0
    assert_select "section.bookkeeping-import-group h2", "Betriebseinnahmen"
    assert_select "section.bookkeeping-import-group h2", "Einlagen und Entnahmen"
  end
end
