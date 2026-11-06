# Gespeicherte Angaben der Nutzerin oder des Nutzers, die bei jeder neuen Rechnung vorausgefüllt werden.
class BusinessProfile < ApplicationRecord
  attribute :invoice_number_format, :string, default: -> { InvoiceNumber::DEFAULT_FORMAT }
  belongs_to :workspace

  def self.for(workspace)
    workspace.business_profile || workspace.build_business_profile(country: "DE")
  end

  def self.remember(invoice)
    profile = self.for(invoice.workspace)
    attributes =
      {
        name: invoice.seller_name, street: invoice.seller_street, postal_code: invoice.seller_postal_code,
        city: invoice.seller_city, country: invoice.seller_country, email: invoice.seller_email, phone: invoice.seller_phone,
        tax_identifier: invoice.seller_tax_identifier, hourly_rate: (invoice.seller_hourly_rate_provided ? invoice.seller_hourly_rate : profile.hourly_rate),
        iban: (invoice.effective_payment_method == "transfer" ? invoice.iban : profile.iban), bic: invoice.bic.presence || profile.bic, tax_mode: invoice.tax_mode
      }
    attributes[:invoice_number_format] = invoice.invoice_number_format unless invoice.invoice_number_format_once
    profile.update!(attributes)
  end

  def invoice_attributes
    {
      seller_hourly_rate: hourly_rate, seller_name: name, seller_street: street, seller_postal_code: postal_code, seller_city: city,
      seller_country: country.presence || "DE", seller_email: email, seller_phone: phone, seller_tax_identifier: tax_identifier,
      iban: iban, bic: bic, tax_mode: tax_mode, invoice_number_format: invoice_number_format
    }
  end

  def euer_details
    details = {}
    details["taxpayer_name"] = name if name.present?
    identifier = tax_identifier.to_s.strip
    details["tax_number"] = identifier if identifier.present? && !identifier.match?(/\A[A-Za-z]{2}/)
    details
  end
end
