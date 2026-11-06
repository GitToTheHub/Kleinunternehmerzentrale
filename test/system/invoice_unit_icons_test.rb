require "application_system_test_case"

class InvoiceUnitIconsTest < ApplicationSystemTestCase
  teardown do
    page.current_window.resize_to(1400, 1100)
  end

  [ 1400, 390 ].each do |width|
    test "quantity icon follows the unit at #{width} pixels" do
      page.current_window.resize_to(width, 1100)
      visit new_invoice_path
      within "[data-invoice-lines-target='row']" do
        assert_selector ".rich-text__editor", visible: true
        assert_selector "[data-line-quantity-target='hourIcon'] svg"
        assert_no_selector "[data-line-quantity-target='quantityIcon'] svg"
        select "Pauschal", from: "Einheit"
        assert_no_selector ".invoice-line__quantity"
        assert_field "Pauschalpreis"
        select "Stunde", from: "Einheit"
        [ "Stunde", "Stück", "Tag", "Monat" ].each do |unit|
          select unit, from: "Einheit"
          icon = { "Stunde" => "hourIcon", "Stück" => "packagesIcon", "Tag" => "calendarIcon", "Monat" => "calendarIcon" }.fetch(unit)
          assert_selector "[data-line-quantity-target='#{icon}'] svg"
          assert page.evaluate_script(<<~JS)
            (() => {
              const price = document.querySelector('[data-line-quantity-target="price"]');
              const title = document.querySelector('[name$="[description]"]');
              return getComputedStyle(price).paddingLeft === getComputedStyle(title).paddingLeft;
            })()
          JS
        end
        select "Stück", from: "Einheit"
        assert_selector "[data-line-quantity-target='packagesIcon'] svg"
        assert_no_selector "[data-line-quantity-target='hourIcon'] svg"
        select "Stunde", from: "Einheit"
        assert_selector "[data-line-quantity-target='hourIcon'] svg"
        assert_no_selector "[data-line-quantity-target='quantityIcon'] svg"
      end
      click_button "Position hinzufügen"
      within all("[data-invoice-lines-target='row']").last do
        assert_selector ".rich-text__editor", visible: true
        assert_select "Einheit", selected: "Stunde"
        assert_selector "[data-line-quantity-target='hourIcon'] svg"
      end
    end
  end
end
