require "test_helper"

class ExpenseSearchTest < ActionDispatch::IntegrationTest
  test "expense search is local optional and contains only valid expense categories" do
    assert_no_difference "Workspace.count" do
      get new_bookkeeping_entry_path(kind: "expense")
      assert_response :success
      assert_select "[data-controller='expense-search']:not([hidden])" do |elements|
        categories = JSON.parse(elements.first["data-expense-search-categories-value"])
        assert_equal BookkeepingEntry::SMALL_BUSINESS_CATEGORIES.fetch("expense"), categories.map { |category| category["key"] }
        assert categories.find { |category| category["key"] == "expense_it" }["terms"].include?("vps")
      end
      assert_select "details.expense-search:not([open])"
      assert_select "[data-euer-entry-target='categoryChoice'] + details.expense-search"
      assert_select "input#expense-category-search:not([name]):not([required])"
      assert_select "select#bookkeeping_entry_category option[value='expense_other']"
      get new_bookkeeping_entry_path(kind: "income")
      assert_select "[data-controller='expense-search'][hidden]"
    end
  end
end
