# Gespeicherte Angaben der Nutzerin oder des Nutzers, die bei jeder neuen Rechnung vorausgefüllt werden.
class BusinessProfile < ApplicationRecord
  belongs_to :workspace

  def self.for(workspace)
    workspace.business_profile || workspace.build_business_profile(country: "DE")
  end

  def self.remember(invoice)
    profile = self.for(invoice.workspace)
    profile.update!(
      name: invoice.seller_name, street: invoice.seller_street, postal_code: invoice.seller_postal_code,
      city: invoice.seller_city, country: invoice.seller_country, email: invoice.seller_email,
      tax_identifier: invoice.seller_tax_identifier, hourly_rate: invoice.latest_hourly_rate || profile.hourly_rate,
      iban: invoice.iban, bic: invoice.bic.presence || profile.bic, tax_mode: invoice.tax_mode
    )
  end

  def invoice_attributes
    {
      seller_name: name, seller_street: street, seller_postal_code: postal_code, seller_city: city,
      seller_country: country.presence || "DE", seller_email: email, seller_tax_identifier: tax_identifier,
      iban: iban, bic: bic, tax_mode: tax_mode
    }
  end
end
