require "test_helper"

class BookkeepingRefundsTest < ActionDispatch::IntegrationTest
  setup do
    post bookkeeping_entries_url, params: { bookkeeping_entry: { kind: "expense", category: "expense_meals", paid_on: Date.current - 2,
      description: "Geschäftliche Bewirtung", amount: "100", payment_account: "private" } }
    @original = BookkeepingEntry.order(:id).last
  end

  def refund_attributes
    { paid_on: Date.current, amount: "40", payment_account: "business", description: "Teilweise erstattet" }
  end

  test "refund form replaces manual choice and copies tax treatment securely" do
    get new_bookkeeping_entry_url
    assert_select "label", text: /Erstattung \/ Rückzahlung/, count: 0
    get refund_bookkeeping_entry_url(@original)
    assert_response :success
    assert_select "select[name='bookkeeping_entry[kind]']", count: 0
    assert_select "select[name='bookkeeping_entry[category]']", count: 0
    assert_difference "BookkeepingEntry.count" do
      post create_refund_bookkeeping_entry_url(@original), params: { bookkeeping_entry: refund_attributes.merge(kind: "income", category: "income_small", reversal: false) }
    end
    assert_response :redirect
    refund = @original.refunds.first
    assert refund.reversal?
    assert_equal "expense", refund.kind
    assert_equal "expense_meals", refund.category
    assert_equal(-28, refund.deductible_amount)
    assert_equal 60, @original.refundable_amount
    assert_nil refund.invoice_id
    patch bookkeeping_entry_url(refund), params: { bookkeeping_entry: refund_attributes.merge(amount: "50", kind: "income") }
    assert_response :redirect
    assert_equal "expense", refund.reload.kind
    assert_equal 50, refund.amount
  end

  test "refunds cannot exceed original amount or precede original payment" do
    post create_refund_bookkeeping_entry_url(@original), params: { bookkeeping_entry: refund_attributes }
    [ refund_attributes.merge(amount: "61"), refund_attributes.merge(paid_on: Date.current - 3), refund_attributes.merge(paid_on: Date.current + 1) ].each do |attrs|
      assert_no_difference "BookkeepingEntry.count" do
        post create_refund_bookkeeping_entry_url(@original), params: { bookkeeping_entry: attrs }
      end
      assert_response :unprocessable_entity
    end
    post create_refund_bookkeeping_entry_url(@original), params: { bookkeeping_entry: refund_attributes.merge(amount: "60") }
    assert_response :redirect
    assert_not @original.refundable?
    get refund_bookkeeping_entry_url(@original)
    assert_response :not_found
  end

  test "refund links respect workspace boundaries and original cannot be deleted first" do
    other = workspaces(:one).bookkeeping_entries.create!(kind: "income", description: "Andere Einnahme", paid_on: Date.current, amount: 100)
    get refund_bookkeeping_entry_url(other)
    assert_response :not_found
    post create_refund_bookkeeping_entry_url(other), params: { bookkeeping_entry: refund_attributes }
    assert_response :not_found
    post create_refund_bookkeeping_entry_url(@original), params: { bookkeeping_entry: refund_attributes }
    refund = @original.refunds.first
    assert_no_difference "BookkeepingEntry.count" do
      delete bookkeeping_entry_url(@original)
    end
    patch bookkeeping_entry_url(@original), params: { bookkeeping_entry: { amount: "30" } }
    assert_response :unprocessable_entity
    delete bookkeeping_entry_url(refund)
    assert_response :see_other
    delete bookkeeping_entry_url(@original)
    assert_not BookkeepingEntry.exists?(@original.id)
  end
end
