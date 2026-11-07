# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_07_090000) do
  create_table "asset_depreciations", force: :cascade do |t|
    t.integer "business_asset_id", null: false
    t.integer "year", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.decimal "special_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "reason", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_asset_id", "year"], name: "index_asset_depreciations_on_business_asset_id_and_year", unique: true
    t.index ["business_asset_id"], name: "index_asset_depreciations_on_business_asset_id"
  end

  create_table "asset_private_uses", force: :cascade do |t|
    t.integer "business_asset_id", null: false
    t.integer "year", null: false
    t.decimal "business_percent", precision: 5, scale: 2, null: false
    t.text "basis", null: false
    t.string "calculation_mode", default: "depreciation", null: false
    t.decimal "manual_amount", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_asset_id", "year"], name: "index_asset_private_uses_on_business_asset_id_and_year", unique: true
    t.index ["business_asset_id"], name: "index_asset_private_uses_on_business_asset_id"
  end

  create_table "bookkeeping_entries", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.date "paid_on", null: false
    t.string "kind", null: false
    t.string "description", null: false
    t.string "reference"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category"
    t.integer "tax_year"
    t.decimal "vat_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "deductible_percent", precision: 5, scale: 2
    t.string "payment_account", default: "business", null: false
    t.boolean "reversal", default: false, null: false
    t.integer "invoice_id"
    t.integer "original_entry_id"
    t.decimal "business_percent", precision: 5, scale: 2, default: "100.0", null: false
    t.text "usage_notes"
    t.string "cash_usage"
    t.decimal "cash_private_amount", precision: 12, scale: 2
    t.index ["invoice_id"], name: "index_bookkeeping_entries_on_invoice_id", unique: true
    t.index ["original_entry_id"], name: "index_bookkeeping_entries_on_original_entry_id"
    t.index ["workspace_id", "paid_on"], name: "index_bookkeeping_entries_on_workspace_id_and_paid_on"
    t.index ["workspace_id"], name: "index_bookkeeping_entries_on_workspace_id"
  end

  create_table "bookkeeping_imports", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "year", null: false
    t.date "covered_through", null: false
    t.string "source", null: false
    t.json "amounts", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "assets_managed_separately", default: false, null: false
    t.json "details", default: {}, null: false
    t.text "notes", default: "", null: false
    t.index ["workspace_id", "year"], name: "index_bookkeeping_imports_on_workspace_id_and_year", unique: true
    t.index ["workspace_id"], name: "index_bookkeeping_imports_on_workspace_id"
  end

  create_table "business_assets", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.string "name", null: false
    t.string "reference"
    t.date "acquired_on", null: false
    t.string "origin", default: "purchase", null: false
    t.string "category", default: "office", null: false
    t.decimal "cost", precision: 12, scale: 2, null: false
    t.string "depreciation_method", default: "linear", null: false
    t.integer "useful_life"
    t.decimal "gwg_net_value", precision: 12, scale: 2
    t.date "paid_on"
    t.string "payment_account", default: "business", null: false
    t.decimal "input_vat", precision: 12, scale: 2, default: "0.0", null: false
    t.date "disposed_on"
    t.string "disposal_kind"
    t.decimal "withdrawal_value", precision: 12, scale: 2
    t.decimal "withdrawal_vat", precision: 12, scale: 2, default: "0.0", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "disposal_recognized_on"
    t.decimal "business_use_percent", precision: 5, scale: 2, default: "100.0", null: false
    t.text "usage_basis"
    t.index ["workspace_id"], name: "index_business_assets_on_workspace_id"
  end

  create_table "business_profiles", force: :cascade do |t|
    t.string "name"
    t.string "street"
    t.string "postal_code"
    t.string "city"
    t.string "country"
    t.string "email"
    t.string "tax_identifier"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "hourly_rate", precision: 12, scale: 2
    t.string "iban"
    t.string "bic"
    t.string "tax_mode", default: "small_business", null: false
    t.integer "workspace_id", null: false
    t.string "invoice_number_format", default: "[Rechnungstyp]-[Jahr]-[Fortlaufendenummer]", null: false
    t.string "phone"
    t.index ["workspace_id"], name: "index_business_profiles_on_workspace_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "name"
    t.string "street"
    t.string "postal_code"
    t.string "city"
    t.string "country"
    t.string "email"
    t.string "leitweg_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "hourly_rate", precision: 12, scale: 2
    t.integer "payment_due_days", default: 14
    t.string "payment_terms"
    t.integer "workspace_id", null: false
    t.string "contact_name"
    t.string "invoice_abbreviation"
    t.index ["name"], name: "index_customers_on_name"
    t.index ["workspace_id"], name: "index_customers_on_workspace_id"
  end

  create_table "euer_adjustments", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "year", null: false
    t.string "field_key", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.text "description", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id"], name: "index_euer_adjustments_on_workspace_id"
  end

  create_table "euer_expense_policies", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "year", null: false
    t.string "deduction_method", default: "actual", null: false
    t.boolean "eligibility_confirmed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "home_office_method", default: "none", null: false
    t.integer "home_days", default: 0, null: false
    t.integer "home_months", default: 0, null: false
    t.boolean "home_eligibility_confirmed", default: false, null: false
    t.text "home_basis"
    t.json "daycare_rows", default: [], null: false
    t.boolean "daycare_eligibility_confirmed", default: false, null: false
    t.index ["workspace_id", "year"], name: "index_euer_expense_policies_on_workspace_id_and_year", unique: true
    t.index ["workspace_id"], name: "index_euer_expense_policies_on_workspace_id"
  end

  create_table "euer_statements", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "year", null: false
    t.json "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "year"], name: "index_euer_statements_on_workspace_id_and_year", unique: true
    t.index ["workspace_id"], name: "index_euer_statements_on_workspace_id"
  end

  create_table "invoice_drafts", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.json "data", default: {}, null: false
    t.string "status", default: "active", null: false
    t.string "form_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "resume_section"
    t.index ["workspace_id", "form_token"], name: "index_invoice_drafts_on_workspace_id_and_form_token", unique: true
    t.index ["workspace_id", "status", "updated_at"], name: "index_invoice_drafts_on_workspace_id_and_status_and_updated_at"
    t.index ["workspace_id"], name: "index_invoice_drafts_on_workspace_id"
  end

  create_table "invoice_lines", force: :cascade do |t|
    t.integer "invoice_id", null: false
    t.string "description"
    t.decimal "quantity", precision: 12, scale: 3
    t.decimal "unit_price", precision: 12, scale: 2
    t.string "unit_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "details"
    t.decimal "tax_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.index ["invoice_id"], name: "index_invoice_lines_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.string "invoice_number"
    t.date "issued_on"
    t.date "service_on"
    t.string "seller_name"
    t.string "seller_street"
    t.string "seller_postal_code"
    t.string "seller_city"
    t.string "seller_country"
    t.string "seller_email"
    t.string "seller_tax_identifier"
    t.string "seller_tax_id_kind"
    t.string "seller_vat_id"
    t.string "buyer_name"
    t.string "buyer_street"
    t.string "buyer_postal_code"
    t.string "buyer_city"
    t.string "buyer_country"
    t.string "buyer_email"
    t.string "buyer_leitweg_id"
    t.string "payment_terms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "buyer_order_number"
    t.date "service_until_on"
    t.string "iban"
    t.string "bic"
    t.date "payment_due_on"
    t.string "tax_mode", default: "small_business", null: false
    t.integer "workspace_id", null: false
    t.integer "cancelled_invoice_id"
    t.string "buyer_contact_name"
    t.string "invoice_number_format", default: "[Rechnungstyp]-[Jahr]-[Fortlaufendenummer]", null: false
    t.integer "invoice_number_sequence"
    t.string "buyer_abbreviation"
    t.integer "invoice_number_daily_sequence"
    t.integer "customer_id"
    t.string "seller_phone"
    t.string "currency", default: "EUR", null: false
    t.decimal "exchange_rate", precision: 18, scale: 8
    t.date "exchange_rate_on"
    t.string "exchange_rate_source"
    t.string "title"
    t.string "payment_method"
    t.boolean "paid", default: false, null: false
    t.integer "corrected_invoice_id"
    t.string "billing_kind", default: "regular", null: false
    t.integer "billing_root_id"
    t.json "deducted_payments", default: [], null: false
    t.integer "sales_document_id"
    t.json "order_snapshot", default: {}, null: false
    t.string "allocation_mode"
    t.decimal "allocation_percent", precision: 7, scale: 2
    t.decimal "allocation_amount", precision: 14, scale: 2
    t.index ["billing_root_id"], name: "index_invoices_on_billing_root_id"
    t.index ["cancelled_invoice_id"], name: "index_invoices_on_cancelled_invoice_id", unique: true
    t.index ["corrected_invoice_id"], name: "index_invoices_on_corrected_invoice_id"
    t.index ["customer_id"], name: "index_invoices_on_customer_id"
    t.index ["sales_document_id"], name: "index_invoices_on_sales_document_id"
    t.index ["workspace_id", "invoice_number"], name: "index_invoices_on_workspace_id_and_invoice_number", unique: true
    t.index ["workspace_id"], name: "index_invoices_on_workspace_id"
  end

  create_table "sales_documents", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.string "kind", null: false
    t.string "document_number", null: false
    t.integer "number_sequence", null: false
    t.date "document_date", null: false
    t.json "data", default: {}, null: false
    t.decimal "total_amount", precision: 14, scale: 2, null: false
    t.integer "source_offer_id"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_offer_id"], name: "index_sales_documents_on_source_offer_id", unique: true
    t.index ["workspace_id", "document_number"], name: "index_sales_documents_on_workspace_id_and_document_number", unique: true
    t.index ["workspace_id"], name: "index_sales_documents_on_workspace_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "token", null: false
    t.string "email"
    t.string "password_digest"
    t.datetime "last_active_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "completed_steps"
    t.datetime "email_confirmed_at"
    t.json "invoice_draft"
    t.datetime "invoice_draft_updated_at"
    t.string "invoice_draft_id"
    t.json "workflow_settings", default: {}, null: false
    t.index ["email"], name: "index_workspaces_on_email", unique: true
    t.index ["invoice_draft_id"], name: "index_workspaces_on_invoice_draft_id", unique: true
    t.index ["last_active_at"], name: "index_workspaces_on_last_active_at"
    t.index ["token"], name: "index_workspaces_on_token", unique: true
  end

  add_foreign_key "asset_depreciations", "business_assets"
  add_foreign_key "asset_private_uses", "business_assets"
  add_foreign_key "bookkeeping_entries", "bookkeeping_entries", column: "original_entry_id"
  add_foreign_key "bookkeeping_entries", "invoices"
  add_foreign_key "bookkeeping_entries", "workspaces"
  add_foreign_key "bookkeeping_imports", "workspaces"
  add_foreign_key "business_assets", "workspaces"
  add_foreign_key "business_profiles", "workspaces"
  add_foreign_key "customers", "workspaces"
  add_foreign_key "euer_adjustments", "workspaces"
  add_foreign_key "euer_expense_policies", "workspaces"
  add_foreign_key "euer_statements", "workspaces"
  add_foreign_key "invoice_drafts", "workspaces"
  add_foreign_key "invoice_lines", "invoices"
  add_foreign_key "invoices", "customers"
  add_foreign_key "invoices", "invoices", column: "billing_root_id"
  add_foreign_key "invoices", "invoices", column: "cancelled_invoice_id"
  add_foreign_key "invoices", "invoices", column: "corrected_invoice_id"
  add_foreign_key "invoices", "sales_documents"
  add_foreign_key "invoices", "workspaces"
  add_foreign_key "sales_documents", "sales_documents", column: "source_offer_id"
  add_foreign_key "sales_documents", "workspaces"
end
