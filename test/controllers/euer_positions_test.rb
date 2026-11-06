require "test_helper"

class EuerPositionsTest < ActionDispatch::IntegrationTest
  test "expense selection shows EÜR positions instead of everyday names" do
    get new_bookkeeping_entry_path(kind: "expense")
    assert_select "label[for='bookkeeping_entry_category']", "Ausgabenart"
    assert_select "#bookkeeping_entry_category option[value='expense_it']", "Laufende EDV-Kosten (z. B. Beratung, Wartung, Reparatur)"
    assert_select "#bookkeeping_entry_category option[value='expense_phone']", /Aufwendungen für Telekommunikation/
    assert_select "#bookkeeping_entry_category option[value='expense_it']", text: /Software und Online-Dienste/, count: 0
    assert_select "fieldset#expense-area-cards input[type=radio]", count: BookkeepingEntriesHelper::EXPENSE_GROUPS.size
    assert_select "[data-euer-entry-target='dateField'][hidden]"
    assert_select "details.expense-search:not([open])"
    assert_select "[data-euer-entry-target='euerReference']", count: 0
    assert_select "a[data-euer-entry-target='euerSource']", count: 0
  end

  test "expense groups cover each position exactly once" do
    keys = BookkeepingEntriesHelper::EXPENSE_GROUPS.values.flatten
    assert_equal BookkeepingEntry::EXPENSE_CATEGORIES.sort, keys.sort
    assert_equal keys.uniq, keys
    get new_bookkeeping_entry_path(kind: "expense")
    assert_select "option[value='expense_it'][data-expense-group='Telefon, Internet und EDV']"
    assert_select "option[value='expense_goods'][data-expense-group='Waren, Versand und Entsorgung']"
  end

  test "booking labels have no line numbers even for unsupported years" do
    label = ApplicationController.helpers.bookkeeping_category_label("expense_it", 2022)
    assert_equal "Laufende EDV-Kosten (z. B. Beratung, Wartung, Reparatur)", label
  end
end
