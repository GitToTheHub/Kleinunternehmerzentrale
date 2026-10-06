require "test_helper"

class WorkspacesTest < ActionDispatch::IntegrationTest
  def invoice_params(name = "Kundin GmbH")
    {
      invoice: {
        issued_on: "2026-10-05", service_on: "2026-10-05", seller_name: "Muster", seller_street: "Weg 1",
        seller_postal_code: "20095", seller_city: "Hamburg", seller_country: "DE", seller_tax_identifier: "12/345/67890",
        buyer_name: name, buyer_street: "Straße 2", buyer_postal_code: "10115", buyer_city: "Berlin", buyer_country: "DE",
        invoice_lines_attributes: { "0" => { description: "Arbeit", quantity: "1", unit_price: "10", unit_code: "HUR" } }
      }
    }
  end

  test "Besucher ohne Eingabe bekommen keinen Bereich" do
    assert_no_difference "Workspace.count" do
      get new_invoice_url
      get invoices_url
    end
  end

  test "die erste Rechnung legt einen Gast-Bereich an und der Hinweis erscheint" do
    assert_difference "Workspace.count", 1 do
      post invoices_url, params: invoice_params
    end
    follow_redirect!
    assert_select ".guest-notice", /3 Monate/
    assert_equal Workspace.last, Invoice.last.workspace
  end

  test "Rechnungen anderer Bereiche sind nicht erreichbar" do
    other = invoices(:one)
    get invoice_url(other)
    assert_response :not_found

    post invoices_url, params: invoice_params
    get invoice_url(other)
    assert_response :not_found
    get invoices_url
    assert_select ".invoice-list__item", 1
  end

  test "Rechnungsnummern zählen je Bereich" do
    post invoices_url, params: invoice_params
    assert_equal "RE-2026-0001", Invoice.last.invoice_number
  end

  test "Konto anlegen übernimmt die bisherigen Daten und Anmelden auf anderem Gerät funktioniert" do
    post invoices_url, params: invoice_params
    workspace = Workspace.last

    post account_url, params: { email: "Ich@Example.de", password: "geheimes-passwort", password_confirmation: "geheimes-passwort" }
    assert_redirected_to invoices_url
    assert_equal workspace, Workspace.find_by(email: "ich@example.de")
    assert_equal 1, workspace.invoices.count

    delete session_url
    get invoices_url
    assert_select ".invoice-list__item", 0

    post session_url, params: { email: "ich@example.de", password: "falsch" }
    assert_response :unprocessable_entity
    post session_url, params: { email: "ich@example.de", password: "geheimes-passwort" }
    get invoices_url
    assert_select ".invoice-list__item", 1
    assert_select ".guest-notice", /bestätige deine E-Mail/
  end

  test "Konto braucht ein ausreichend langes Passwort" do
    post invoices_url, params: invoice_params
    post account_url, params: { email: "a@example.de", password: "kurz", password_confirmation: "kurz" }
    assert_response :unprocessable_entity
    assert_nil Workspace.last.email
  end

  test "Gast-Bereiche werden nach drei Monaten ohne Nutzung gelöscht, Konten und aktive nicht" do
    old = Workspace.create!(last_active_at: 4.months.ago)
    account = Workspace.create!(last_active_at: 4.months.ago, email: "x@example.de", password: "geheimes-passwort", email_confirmed_at: Time.current)
    fresh = Workspace.create!(last_active_at: 2.months.ago)
    old.customers.create!(name: "Alt")

    Workspace.purge_expired_guests

    assert_not Workspace.exists?(old.id)
    assert_equal 0, Customer.where(workspace_id: old.id).count
    assert Workspace.exists?(account.id)
    assert Workspace.exists?(fresh.id)
  end

  test "Alle Daten löschen entfernt den Bereich" do
    post invoices_url, params: invoice_params
    assert_difference "Workspace.count", -1 do
      delete account_url
    end
    assert_equal 0, Invoice.where(buyer_name: "Kundin GmbH").count
  end

  test "gespeicherte Rechnungen lassen sich nicht mehr ändern" do
    post invoices_url, params: invoice_params
    invoice = Invoice.last
    assert_raises(ActiveRecord::ReadOnlyRecord) { invoice.update!(buyer_name: "Anders") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { invoice.invoice_lines.first.update!(unit_price: 1) }
  end

  test "Startseite zeigt immer nur den nächsten Schritt und merkt sich erledigte" do
    get root_url
    assert_select ".start-guide h2", "Tätigkeit anmelden"
    assert_select ".start-guide", /Schritt 1 von 5/

    patch start_step_url("anmelden")
    follow_redirect!
    assert_select ".start-guide h2", "Fragebogen vom Finanzamt ausfüllen"

    patch start_step_url("unbekannt")
    patch start_step_url("finanzamt")
    get root_url
    assert_select ".start-guide h2", "Erste Rechnung schreiben"

    post invoices_url, params: invoice_params
    get root_url
    assert_select ".start-guide h2", "Einnahmen und Ausgaben aufschreiben"
  end

  test "nach der ersten Rechnung gibt es einen Hinweis, nach der zweiten nicht" do
    post invoices_url, params: invoice_params
    follow_redirect!
    assert_select ".first-invoice-tip", /8 Jahre/

    post invoices_url, params: invoice_params("Zweite AG")
    follow_redirect!
    assert_select ".first-invoice-tip", 0
  end

  test "Rechnung stornieren: Stornorechnung mit negativen Beträgen, Verweis in der XRechnung, Vorlage für die Korrektur" do
    post invoices_url, params: invoice_params.deep_merge(invoice: { seller_email: "a@example.de", buyer_email: "b@example.de" })
    original = Invoice.last

    assert_difference "Invoice.count", 1 do
      post cancel_invoice_url(original)
    end
    assert_redirected_to new_invoice_url(copy_from: original.id)
    storno = original.reload.cancellation
    assert storno.cancellation?
    assert_equal(-10, storno.total)
    assert_equal original.net_total, -storno.net_total

    get invoice_url(storno)
    assert_select ".eyebrow", "Stornorechnung"
    assert_select ".invoice-cancellation-note", /#{original.invoice_number}/

    get xrechnung_invoice_url(storno)
    assert_includes response.body, "<ram:TypeCode>384</ram:TypeCode>"
    assert_match %r{<ram:InvoiceReferencedDocument>\s*<ram:IssuerAssignedID>#{original.invoice_number}</ram:IssuerAssignedID>}, response.body

    get invoice_url(original)
    assert_select ".invoice-status", /storniert durch #{storno.invoice_number}/

    get new_invoice_url(copy_from: original.id)
    assert_select "input[name='invoice[buyer_name]'][value='Kundin GmbH']"
    assert_select "input[name='invoice[invoice_lines_attributes][0][unit_price]'][value='10.0']"

    assert_no_difference "Invoice.count" do
      post cancel_invoice_url(original)
      post cancel_invoice_url(storno)
    end
  end

  test "fremde Rechnungen lassen sich nicht stornieren" do
    assert_no_difference "Invoice.count" do
      post cancel_invoice_url(invoices(:one))
    end
    assert_response :not_found
  end

  test "Storno zählt beim Umsatz mit und hebt ihn auf" do
    post invoices_url, params: invoice_params
    original = Invoice.last
    post cancel_invoice_url(original)
    assert_equal 0, RevenueLimits.new(original.workspace).current_revenue
  end

  test "Datenexport liefert ZIP mit CSV und XRechnung nur für den eigenen Bereich" do
    get export_url
    assert_redirected_to invoices_url

    post invoices_url, params: invoice_params.deep_merge(invoice: { seller_email: "a@example.de", buyer_email: "b@example.de", buyer_name: "=Evil" })
    number = Invoice.last.invoice_number

    get export_url
    assert_response :success
    entries = {}
    Zip::InputStream.open(StringIO.new(response.body)) do |zip|
      while (entry = zip.get_next_entry)
        entries[entry.name] = zip.read.force_encoding("UTF-8")
      end
    end
    assert_equal %w[absender.csv kunden.csv positionen.csv rechnungen.csv xrechnung/#{number}.xml].sort, entries.keys.sort.map { |k| k.sub(number, '#{number}') }
    assert_includes entries["rechnungen.csv"], number
    assert_includes entries["rechnungen.csv"], "'=Evil"
    assert_not_includes entries["rechnungen.csv"], invoices(:one).invoice_number
  end

  test "Spendenseite verlinkt GitHub Sponsors" do
    get spenden_url
    assert_response :success
    assert_select "a[href='https://github.com/sponsors/GitToTheHub']"
  end
end
