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

ActiveRecord::Schema[8.1].define(version: 2026_10_06_150001) do
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
    t.index ["name"], name: "index_customers_on_name"
    t.index ["workspace_id"], name: "index_customers_on_workspace_id"
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
    t.index ["cancelled_invoice_id"], name: "index_invoices_on_cancelled_invoice_id", unique: true
    t.index ["workspace_id", "invoice_number"], name: "index_invoices_on_workspace_id_and_invoice_number", unique: true
    t.index ["workspace_id"], name: "index_invoices_on_workspace_id"
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
    t.index ["email"], name: "index_workspaces_on_email", unique: true
    t.index ["last_active_at"], name: "index_workspaces_on_last_active_at"
    t.index ["token"], name: "index_workspaces_on_token", unique: true
  end

  add_foreign_key "business_profiles", "workspaces"
  add_foreign_key "customers", "workspaces"
  add_foreign_key "invoice_lines", "invoices"
  add_foreign_key "invoices", "invoices", column: "cancelled_invoice_id"
  add_foreign_key "invoices", "workspaces"
end
