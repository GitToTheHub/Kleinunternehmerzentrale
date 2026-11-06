# Strict decimal input shared by tax records; Active Record alone would round or
# accept the numeric prefix of malformed input.
module EuroAmounts
  extend ActiveSupport::Concern

  class_methods do
    def euro_amounts(*attributes, signed: false)
      attributes.each do |attribute|
        define_method("#{attribute}=") do |value|
          if value.is_a?(String) && value.present?
            value = value.strip
            if value.include?(",")
              german_pattern = signed ? /\A-?(?:\d+|\d{1,3}(?:\.\d{3})+),\d{1,2}\z/ : /\A(?:\d+|\d{1,3}(?:\.\d{3})+),\d{1,2}\z/
              value = value.match?(german_pattern) ? value.delete(".").tr(",", ".") : "invalid"
            end
            pattern = signed ? /\A-?\d+(?:\.\d{1,2})?\z/ : /\A\d+(?:\.\d{1,2})?\z/
            value = "invalid" unless value.match?(pattern)
          end
          super(value)
        end
        validate do
          raw = public_send("#{attribute}_before_type_cast")
          if raw == "invalid" || (raw.is_a?(Numeric) && (raw.to_d * 100) % 1 != 0)
            errors.add(attribute, "muss ein gültiger Betrag mit höchstens zwei Nachkommastellen sein")
          end
        end
      end
    end
  end
end
