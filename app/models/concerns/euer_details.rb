module EuerDetails
  extend ActiveSupport::Concern
  included do
    validate :valid_euer_details
  end

  private

  def valid_euer_details
    unless details.is_a?(Hash) && (details.keys - EuerForm::DETAILS.keys).empty?
      errors.add(:details, "enthält unbekannte Betriebsangaben")
      return
    end
    details.each do |key, value|
      next if value.blank?

      type = EuerForm::DETAILS.fetch(key).last
      if !value.is_a?(String) || value.length > 500 || (type.is_a?(Hash) && !type.key?(value))
        errors.add(:details, "enthält einen ungültigen Wert für #{EuerForm::DETAILS.fetch(key)[1]}")
      elsif type == :date
        begin
          Date.iso8601(value)
        rescue Date::Error
          errors.add(:details, "enthält ein ungültiges Datum")
        end
      end
    end
    if details["period_start"].present? != details["period_end"].present?
      errors.add(:details, "muss Beginn und Ende des abweichenden Wirtschaftsjahrs enthalten")
    elsif details["period_start"].is_a?(String) && details["period_end"].is_a?(String) && details["period_end"] < details["period_start"]
      errors.add(:details, "muss ein Ende nach dem Beginn des Wirtschaftsjahrs enthalten")
    end
  end
end
