# Gespeicherte Kundinnen und Kunden, die auf neuen Rechnungen ausgewählt werden können.
class Customer < ApplicationRecord
  belongs_to :workspace

  scope :alphabetical, -> { order(Arel.sql("LOWER(name)")) }

  def self.remember(invoice)
    customer = invoice.workspace.customers.where("LOWER(name) = ?", invoice.buyer_name.downcase).first_or_initialize
    customer.update!(
      name: invoice.buyer_name, street: invoice.buyer_street, postal_code: invoice.buyer_postal_code,
      city: invoice.buyer_city, country: invoice.buyer_country, email: invoice.buyer_email,
      leitweg_id: invoice.buyer_leitweg_id, hourly_rate: invoice.latest_hourly_rate || customer.hourly_rate,
      payment_due_days: invoice.payment_due_on && invoice.issued_on ? (invoice.payment_due_on - invoice.issued_on).to_i : nil,
      payment_terms: invoice.payment_terms
    )
  end

  def form_values
    {
      buyer_name: name, buyer_email: email, buyer_street: street, buyer_postal_code: postal_code,
      buyer_city: city, buyer_country: country, buyer_leitweg_id: leitweg_id, payment_terms: payment_terms
    }
  end
end
