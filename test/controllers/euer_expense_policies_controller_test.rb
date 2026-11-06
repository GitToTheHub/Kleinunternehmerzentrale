require "test_helper"

class EuerExpensePoliciesControllerTest < ActionDispatch::IntegrationTest
  test "whole business election recalculates reports is reversible and stays scoped" do
    get edit_euer_expense_policy_url(year: 2026)
    assert_response :success
    assert_no_difference "Workspace.count" do
      get edit_euer_expense_policy_url(year: 2025)
    end
    patch euer_statement_url(year: 2026), params: { euer_statement: { details: { legal_form: "Einzelunternehmen", income_type: "3" } } }
    post bookkeeping_entries_url, params: { bookkeeping_entry: { kind: "income", category: "income_small", amount: 2000, description: "Honorar", paid_on: "2026-06-01" } }
    patch euer_expense_policy_url(year: 2026), params: { euer_expense_policy: { deduction_method: "writer_main", eligibility_confirmed: "1", workspace_id: workspaces(:one).id } }
    assert_redirected_to prepare_euer_bookkeeping_entries_path(year: 2026)
    selected = EuerExpensePolicy.last
    assert_not_equal workspaces(:one).id, selected.workspace_id
    get bookkeeping_entries_url(year: 2026)
    assert_select "dd strong", "1.400,00 €"
    get bookkeeping_entries_url(year: 2026, format: :csv)
    assert_includes response.body, "Betriebsausgabenpauschale ersetzt"
    get export_url
    exported = {}
    Zip::InputStream.open(StringIO.new(response.body)) do |zip|
      while (item = zip.get_next_entry)
        exported[item.name] = zip.read.force_encoding("UTF-8")
      end
    end
    assert_includes exported.fetch("euer-ausgabenmethoden.json"), "writer_main"
    other = ActionDispatch::Integration::Session.new(Rails.application)
    other.get edit_euer_expense_policy_url(year: 2026)
    assert_equal "actual", Nokogiri::HTML(other.response.body).at_css("#euer_expense_policy_deduction_method option[selected]")["value"]
    other.patch euer_expense_policy_url(year: 2026), params: { euer_expense_policy: { deduction_method: "writer_main", eligibility_confirmed: "1" } }
    assert_equal 422, other.response.status
    patch euer_expense_policy_url(year: 2026), params: { euer_expense_policy: { deduction_method: "actual" } }
    assert_response :redirect
    assert_equal "actual", selected.reload.deduction_method
    get edit_euer_expense_policy_url(year: 2027)
    assert_response :not_found
  end
end
