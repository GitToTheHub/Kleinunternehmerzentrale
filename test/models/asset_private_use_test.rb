require "test_helper"

class AssetPrivateUseTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!
    @asset = @workspace.business_assets.create!(name: "Mac", acquired_on: "2026-01-01", paid_on: "2026-01-01", cost: 1200, useful_life: 3)
  end

  def usage(**attributes)
    @asset.asset_private_uses.build({ year: 2026, business_percent: 60, basis: "Nutzungsaufzeichnung", calculation_mode: "depreciation" }.merge(attributes))
  end

  def report(year = 2026)
    BookkeepingReport.new(@workspace.bookkeeping_entries, year, assets: @workspace.business_assets)
  end

  test "annual private share offsets depreciation without changing book values" do
    usage.save!
    usage(year: 2027, business_percent: 80).save!
    assert_equal 400, report.expenses
    assert_equal 160, report.income
    assert_equal 160, report.withdrawals
    assert_equal(-240, report.surplus)
    assert_equal 800, @asset.schedule(2026)[:closing]
    assert_equal 80, report(2027).income
    assert_equal 0, report(2028).income
    assert report(2028).warnings.any? { |warning| warning.include?("Jahresnutzung") }
    assert_includes report.csv, "Nutzungsaufzeichnung"
  end

  test "partial year and permanent withdrawal have distinct effects" do
    @asset.update!(acquired_on: "2026-10-01", paid_on: "2026-10-01", disposed_on: "2027-03-01", disposal_kind: "withdrawal", withdrawal_value: 600)
    usage.save!
    usage(year: 2027).save!
    assert_equal 40, report.income
    assert_equal 640, report(2027).income
    assert_equal 640, report(2027).withdrawals
    assert_equal 0, @asset.schedule(2027)[:closing]
  end

  test "contribution and private payment equity are not reduced by annual usage" do
    @asset.update!(origin: "contribution", paid_on: nil)
    usage.save!
    assert_equal 1200, report.deposits
    assert_equal 160, report.withdrawals
    @asset.update!(origin: "purchase", paid_on: "2026-01-01", payment_account: "private")
    assert_equal 1200, report.deposits
  end

  test "special cases require manual values and preserve their EÜR field" do
    @asset.update!(category: "vehicle")
    record = usage
    assert_not record.valid?
    record.assign_attributes(calculation_mode: "manual", manual_amount: "123,45")
    assert record.save, record.errors.full_messages.to_sentence
    assert_equal BigDecimal("123.45"), report.field_totals["vehicle_use"]
    assert_equal BigDecimal("123.45"), report.withdrawals
    assert_not record.update(business_percent: 100)
    assert record.update(business_percent: 100, manual_amount: 0)
  end

  test "special depreciation cannot be silently omitted from calculated private use" do
    usage.save!
    @asset.asset_depreciations.build(year: 2026, amount: 400, special_amount: 100, reason: "Sonderabschreibung")
    assert_not @asset.valid?
    assert @asset.errors.full_messages.join.include?("Sonderfall")
  end

  test "validates evidence years duplicate years bounds and later parent changes" do
    first = usage
    assert_not first.update(basis: "")
    first.basis = "Nutzungsaufzeichnung"
    first.save!
    duplicate = usage
    assert_not duplicate.valid?
    @asset.asset_private_uses.delete(duplicate)
    assert_not first.update(year: 2025)
    assert_not first.update(year: 2026, business_percent: 101)
    assert first.update(business_percent: "60,5")
    assert_equal 158, first.amount
    assert_not @asset.update(disposed_on: "2025-12-31", disposal_kind: "scrap")
  end

  test "nested blank rows are ignored and removing usage reverses its effect" do
    assert @asset.update(asset_private_uses_attributes: [ { year: "", business_percent: "", basis: "", calculation_mode: "depreciation" } ])
    assert_empty @asset.asset_private_uses
    record = usage
    record.save!
    assert @asset.update(asset_private_uses_attributes: [ { id: record.id, _destroy: "1" } ])
    assert_equal 0, report.income
    assert_equal 0, report.withdrawals
  end

  test "import overlap is rejected in either direction" do
    usage.save!
    imported = @workspace.bookkeeping_imports.new(year: 2026, covered_through: "2026-10-01", source: "Altbestand", amounts: { "other_withdrawal" => "160" }, assets_managed_separately: true)
    assert_not imported.valid?
    @asset.asset_private_uses.destroy_all
    imported.save!
    @asset.reload
    usage
    assert_not @asset.save
  end

  test "export includes annual use and asset deletion removes its records" do
    record = usage
    record.save!
    contents = {}
    Zip::InputStream.open(StringIO.new(DataExport.new(@workspace).call)) do |zip|
      while (item = zip.get_next_entry)
        contents[item.name] = zip.read.force_encoding("UTF-8")
      end
    end
    assert_includes contents.fetch("anlagegueter-private-nutzung.csv"), "Nutzungsaufzeichnung"
    assert_includes contents.fetch("anlagegueter-private-nutzung.csv"), "160"
    @asset.destroy!
    assert_not AssetPrivateUse.exists?(record.id)
  end
end
