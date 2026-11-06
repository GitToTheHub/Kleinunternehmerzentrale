require "test_helper"

class ExchangeRateLookupTest < ActiveSupport::TestCase
  CSV_DATA = <<~CSV.freeze
    CURRENCY,CURRENCY_DENOM,TIME_PERIOD,OBS_VALUE
    USD,EUR,2026-10-08,1.25
    USD,EUR,2026-10-09,1.20
    USD,EUR,2026-10-12,1.10
    GBP,EUR,2026-10-09,0.85
  CSV

  def lookup(currency: "USD", date: "2026-10-11", cache: ActiveSupport::Cache::MemoryStore.new)
    ExchangeRateLookup.new(currency: currency, date: date, cache: cache)
  end

  test "Wochenende nimmt letzten Kurs davor und kehrt EZB Notierung korrekt um" do
    travel_to Time.zone.local(2026, 10, 11) do
      service = lookup
      service.define_singleton_method(:download) { |_| CSV_DATA }
      result = service.call
      assert_equal "0.83333333", result[:rate]
      assert_equal "1.2", result[:quote]
      assert_equal "2026-10-09", result[:date]
      assert_equal "EZB-Referenzkurs", result[:source]
    end
  end

  test "historischer Kurs verwendet keine spaetere Beobachtung" do
    service = lookup(date: "2026-10-08")
    service.define_singleton_method(:download) { |_| CSV_DATA }
    result = service.call
    assert_equal "0.8", result[:rate]
    assert_equal "2026-10-08", result[:date]
  end

  test "wiederholter Abruf verwendet Cache statt Netzwerk" do
    service = lookup
    count = 0
    download = ->(*) { count += 1; CSV_DATA }
    service.define_singleton_method(:download, download)
    2.times { service.call }
    assert_equal 1, count
  end

  test "alte Cache Eintraege ohne neue Kursrichtung werden nicht verwendet" do
    travel_to Time.zone.local(2026, 10, 11) do
      cache = ActiveSupport::Cache::MemoryStore.new
      cache.write("ecb-exchange-rate/v1/USD/2026-10-11", { rate: "0.8", date: "2026-10-09", source: "EZB-Referenzkurs" })
      service = lookup(cache: cache)
      service.define_singleton_method(:download) { |_| CSV_DATA }
      assert_equal "1.2", service.call[:quote]
    end
  end

  test "unbekannte Waehrung ungueltiges Datum und fehlende Kurse werden abgelehnt" do
    assert_raises(ExchangeRateLookup::LookupError) { lookup(currency: "INVALID").call }
    assert_raises(ExchangeRateLookup::LookupError) { lookup(date: "2026-02-30") }
    assert_raises(ExchangeRateLookup::LookupError) { lookup(date: "1998-01-01").call }
    service = lookup
    service.define_singleton_method(:download) { |_| "CURRENCY,CURRENCY_DENOM,TIME_PERIOD,OBS_VALUE\nUSD,EUR,2026-10-09,0\n" }
    assert_raises(ExchangeRateLookup::LookupError) { service.call }
    service.define_singleton_method(:download) { |_| "CURRENCY,CURRENCY_DENOM,TIME_PERIOD,OBS_VALUE\nUSD,EUR,2026-10-09,invalid\n" }
    assert_raises(ExchangeRateLookup::LookupError) { service.call }
  end

  test "Netzwerkfehler bleibt als manuell behebbarer Fehler sichtbar" do
    service = lookup
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*| raise SocketError, "offline" }
    assert_raises(ExchangeRateLookup::LookupError) { service.call }
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end
end
