require "test_helper"

class BookkeepingEntriesControllerTest < ActionDispatch::IntegrationTest
  def attributes
    { paid_on: "2026-10-12", kind: "income", description: "Kundenzahlung", amount: "123,45", reference: "RE-1" }
  end

  test "guest can manage payments and download annual preparation" do
    assert_no_difference "Workspace.count" do
      get bookkeeping_entries_url
      assert_response :success
      assert_select ".booking-guidance", count: 0
      get new_bookkeeping_entry_url
      assert_response :success
      assert_select "details.booking-guidance:not([open]) summary", "Hinweis: Was gehört in deine Buchhaltung?"
    end
    assert_difference "BookkeepingEntry.count", 1 do
      post bookkeeping_entries_url, params: { bookkeeping_entry: attributes.merge(workspace_id: workspaces(:one).id) }
    end
    entry = BookkeepingEntry.order(:id).last
    assert_not_equal workspaces(:one), entry.workspace
    follow_redirect!
    assert_select "td", "Kundenzahlung"
    assert_select ".guest-notice"
    get edit_bookkeeping_entry_url(entry)
    assert_response :success
    assert_select ".booking-guidance", count: 0
    patch bookkeeping_entry_url(entry), params: { bookkeeping_entry: { kind: "deposit" } }
    assert_equal "deposit", entry.reload.kind
    get bookkeeping_entries_url(year: 2026, format: :csv)
    assert_response :success
    assert_includes response.body, "123,45"
    get export_url
    names = []
    Zip::InputStream.open(StringIO.new(response.body)) do |zip|
      while (item = zip.get_next_entry)
        names << item.name
      end
    end
    assert_includes names, "buchhaltung.csv"
    delete bookkeeping_entry_url(entry)
    assert_response :see_other
    assert_not BookkeepingEntry.exists?(entry.id)
  end

  test "other workspaces cannot read change or delete entries" do
    other = workspaces(:one).bookkeeping_entries.create!(attributes)
    get edit_bookkeeping_entry_url(other)
    assert_response :not_found
    patch bookkeeping_entry_url(other), params: { bookkeeping_entry: { amount: "1" } }
    assert_response :not_found
    delete bookkeeping_entry_url(other)
    assert_response :not_found
    assert_equal BigDecimal("123.45"), other.reload.amount
    get bookkeeping_entries_url(format: :csv)
    assert_not_includes response.body, "Kundenzahlung"
  end

  test "invalid entry is displayed without saving and invalid years fall back" do
    assert_no_difference "BookkeepingEntry.count" do
      post bookkeeping_entries_url, params: { bookkeeping_entry: attributes.merge(amount: "12,345") }
    end
    assert_response :unprocessable_entity
    get bookkeeping_entries_url(year: "0000")
    assert_response :success
    get bookkeeping_entries_url(year: "2026bad")
    assert_response :success
  end
  test "small business form offers gross amounts and only relevant categories" do
    get new_bookkeeping_entry_url
    assert_response :success
    assert_select "input[name='bookkeeping_entry[vat_amount]']", count: 0
    EuerFields::REGULAR_TAX_KEYS.each do |key|
      assert_select "#bookkeeping_entry_category option[value='#{key}']", count: 0
    end
    %w[income_small asset_income expense_goods expense_meals vat_payment vat_refund].each do |key|
      assert_select "#bookkeeping_entry_category option[value='#{key}']", count: 1
    end
    assert_select "#bookkeeping_entry_category option[value='vat_payment']", /Sonderfall/
    post bookkeeping_entries_url, params: { bookkeeping_entry: attributes.merge(kind: "expense", category: "expense_goods", amount: "119", vat_amount: "19") }
    assert_response :redirect
    item = BookkeepingEntry.order(:id).last
    assert_equal 0, item.vat_amount
    assert_equal 119, item.deductible_amount
  end

  test "new expense has no guessed purpose and explicit blank selection cannot be saved" do
    get new_bookkeeping_entry_url(kind: "expense")
    assert_select "#bookkeeping_entry_category option[value=''][selected]"
    assert_select "#bookkeeping_entry_category option[value='expense_other'][selected]", count: 0
    assert_no_difference "BookkeepingEntry.count" do
      post bookkeeping_entries_url, params: { bookkeeping_entry: attributes.merge(kind: "expense", category: "") }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "Wähle aus, wofür du bezahlt hast."
  end

  test "regular taxation categories cannot be submitted but special VAT payments can" do
    %w[income_taxable income_exempt vat_collected input_vat].each do |key|
      assert_no_difference "BookkeepingEntry.count" do
        post bookkeeping_entries_url, params: { bookkeeping_entry: attributes.merge(category: key) }
      end
      assert_response :unprocessable_entity
    end
    post bookkeeping_entries_url, params: { bookkeeping_entry: attributes.merge(kind: "expense", category: "vat_payment", description: "§ 13b", amount: "19") }
    assert_response :redirect
    assert_equal "vat_payment", BookkeepingEntry.order(:id).last.category
  end

  test "editing older tax data preserves the recorded tax split" do
    post bookkeeping_entries_url, params: { bookkeeping_entry: attributes }
    item = BookkeepingEntry.order(:id).last
    item.update!(category: "income_taxable", amount: 119, vat_amount: 19)
    get edit_bookkeeping_entry_url(item)
    assert_select "#bookkeeping_entry_category option[selected][value='income_taxable']", count: 1
    patch bookkeeping_entry_url(item), params: { bookkeeping_entry: { description: "Altbuchung geprüft", vat_amount: "0" } }
    assert_response :redirect
    assert_equal 19, item.reload.vat_amount
    get bookkeeping_entries_url(year: 2026)
    assert_select "[role='status']", /ältere Angaben zur Regelbesteuerung/
  end
end
