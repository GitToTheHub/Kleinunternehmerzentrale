require "csv"
require "net/http"
require "uri"

# ECB quotes foreign currency per EUR; our stored rate is EUR per foreign unit.
class ExchangeRateLookup
  class LookupError < StandardError; end
  SOURCE = "EZB-Referenzkurs".freeze
  MAX_BYTES = 100_000

  def initialize(currency:, date:, cache: Rails.cache)
    @currency = currency.to_s
    @date = Date.iso8601(date.to_s)
    @cache = cache
  rescue Date::Error
    raise LookupError, "Bitte ergänze ein gültiges Rechnungsdatum."
  end

  def call
    unless %w[USD GBP CHF].include?(@currency)
      raise LookupError, "Für diese Währung ist kein automatischer Kurs verfügbar."
    end
    date = [ @date, Date.current ].min
    raise LookupError, "Für dieses Datum ist kein EZB-Kurs verfügbar. Bitte trage den Kurs manuell ein." if date < Date.new(1999, 1, 4)

    @cache.fetch("ecb-exchange-rate/v2/#{@currency}/#{date}", expires_in: 1.hour) do
      rows = CSV.parse(download(date), headers: true)
      observations = rows.filter_map do |row|
        next unless row["CURRENCY"] == @currency && row["CURRENCY_DENOM"] == "EUR"

        observed_on = Date.iso8601(row["TIME_PERIOD"].to_s)
        value = BigDecimal(row["OBS_VALUE"].to_s)
        next unless observed_on <= date && value.finite? && value.positive?

        [ observed_on, value ]
      end
      observation = observations.max_by(&:first)
      raise LookupError, "Kein EZB-Kurs für dieses Datum gefunden. Bitte trage den Kurs manuell ein." unless observation

      observed_on, value = observation
      { rate: (BigDecimal("1") / value).round(8).to_s("F"), quote: value.to_s("F"), date: observed_on.iso8601, source: SOURCE }
    end
  rescue CSV::MalformedCSVError, ArgumentError, TypeError
    raise LookupError, "Die EZB-Kursdaten konnten nicht gelesen werden. Bitte trage den Kurs manuell ein."
  end

  private

  def download(date)
    uri = URI("https://data-api.ecb.europa.eu/service/data/EXR/D.#{@currency}.EUR.SP00.A")
    uri.query = URI.encode_www_form(startPeriod: (date - 14).iso8601, endPeriod: date.iso8601, format: "csvdata")
    body = +""
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5, write_timeout: 5) do |http|
      http.request(Net::HTTP::Get.new(uri)) do |response|
        raise LookupError, "Die EZB-Kurse sind gerade nicht verfügbar. Bitte trage den Kurs manuell ein." unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          body << chunk
          raise LookupError, "Die EZB-Kursdaten konnten nicht gelesen werden." if body.bytesize > MAX_BYTES
        end
      end
    end
    body
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError
    raise LookupError, "Die EZB-Kurse konnten nicht geladen werden. Bitte versuche es erneut oder trage den Kurs manuell ein."
  end
end
