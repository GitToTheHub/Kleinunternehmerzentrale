# Gespeicherte Kundinnen und Kunden, die auf neuen Rechnungen ausgewählt werden können.
class Customer < ApplicationRecord
  belongs_to :workspace

  scope :alphabetical, -> { order(Arel.sql("LOWER(name)")) }

  def self.remember(invoice)
    if invoice.customer_id.present?
      customer = invoice.workspace.customers.find(invoice.customer_id)
      return customer if invoice.customer_update_mode == "invoice_only" || !invoice.customer_details_changed?
    else
      customer = invoice.workspace.customers.where("LOWER(name) = ?", invoice.buyer_name.downcase).detect do |candidate|
        !candidate.differs_from_invoice?(invoice)
      end
      return customer if customer
      customer = invoice.workspace.customers.new
    end
    customer.update!(customer.attributes_from_invoice(invoice))
    customer
  end

  def attributes_from_invoice(invoice)
    {
      name: invoice.buyer_name, street: invoice.buyer_street, postal_code: invoice.buyer_postal_code,
      city: invoice.buyer_city, country: invoice.buyer_country, email: invoice.buyer_email,
      contact_name: invoice.buyer_contact_name, invoice_abbreviation: invoice.buyer_abbreviation,
      leitweg_id: invoice.buyer_leitweg_id, hourly_rate: (invoice.buyer_hourly_rate_provided || !invoice.buyer_hourly_rate_before_type_cast.nil? ? invoice.buyer_hourly_rate : invoice.uniform_hourly_rate || hourly_rate),
      payment_due_days: invoice.payment_due_on && invoice.issued_on ? (invoice.payment_due_on - invoice.issued_on).to_i : nil,
      payment_terms: invoice.payment_terms
    }
  end

  def differs_from_invoice?(invoice)
    attributes_from_invoice(invoice).any? { |key, value| self[key].to_s != value.to_s }
  end

  def form_values
    {
      buyer_hourly_rate: hourly_rate, buyer_name: name, buyer_abbreviation: invoice_abbreviation, buyer_contact_name: contact_name, buyer_email: email, buyer_street: street, buyer_postal_code: postal_code,
      buyer_city: city, buyer_country: country, buyer_leitweg_id: leitweg_id, payment_terms: payment_terms
    }
  end
end
