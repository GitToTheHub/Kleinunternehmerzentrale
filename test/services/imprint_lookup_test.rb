require "test_helper"

class ImprintLookupTest < ActiveSupport::TestCase
  test "keeps registration labels out of the imprint email" do
    [
      'E-Mail: <a href="mailto:info@netactive.de">info@netactive.de</a>Handelsregister: HRB 36340 HB',
      "E-Mail: info@netactive.de<br>Handelsregister: HRB 36340 HB",
      "E-Mail: info@netactive.deHandelsregister: HRB 36340 HB"
    ].each do |contact|
      result = ImprintLookup.new("netactive.de").send(:extract_fields, "<p>#{contact}</p>")

      assert_equal "info@netactive.de", result[:buyer_email], contact
    end
  end

  test "does not mistake company registration details for a contact person" do
    lookup = ImprintLookup.new("netactive.de")
    [ "Handelsregister: HRB 36340 HB", "Registergericht: Amtsgericht Bremen",
      "Amtsgericht Bremen", "Umsatzsteuer-ID: DE123456789" ].each do |registration|
      html = <<~HTML
        <address>
          netactive GmbH<br>
          Barkhausenstraße 6<br>
          27568 Bremerhaven<br>
          #{registration}
        </address>
      HTML

      result = lookup.send(:extract_fields, html)

      assert_equal "netactive GmbH", result[:buyer_name]
      assert_nil result[:buyer_contact_name], registration
    end
  end

  test "continues past registration details to find a person after the address" do
    html = <<~HTML
      <address>
        Beispiel GmbH<br>Musterstraße 1<br>12345 Berlin<br>
        Handelsregister: HRB 12345<br>Max Mustermann
      </address>
    HTML

    result = ImprintLookup.new("example.org").send(:extract_fields, html)

    assert_equal "Max Mustermann", result[:buyer_contact_name]
  end

  test "prefers imprint billing details over contact details on a domain homepage" do
    lookup = ImprintLookup.new("angelteiche-beverstedt.de")
    homepage = <<~HTML
      <p>Angelteiche Beverstedt<br>Wehldorfer Str. 8<br>27616 Beverstedt</p>
      <p><a href="mailto:team@angelteiche-beverstedt.de">team@angelteiche-beverstedt.de</a></p>
    HTML
    imprint = <<~HTML
      <p>Angelteiche Beverstedt<br>Wehldorfer Straße 8<br>27616 Beverstedt<br>Deutschland</p>
      <p>Telefon: 0176 60419911<br>E-Mail: <a href="mailto:info@angelteiche-beverstedt.de">info@angelteiche-beverstedt.de</a></p>
    HTML
    requested = []
    lookup.define_singleton_method(:fetch_html) do |uri|
      requested << uri.to_s
      [ uri.path == "/" ? homepage : imprint, uri ]
    end

    result = lookup.call

    assert_equal [ "https://angelteiche-beverstedt.de/", "https://angelteiche-beverstedt.de/impressum" ], requested
    assert_equal "Angelteiche Beverstedt", result[:buyer_name]
    assert_equal "info@angelteiche-beverstedt.de", result[:buyer_email]
    assert_equal "Wehldorfer Straße 8", result[:buyer_street]
    assert_equal "DE", result[:buyer_country]
    assert_nil result[:buyer_contact_name]
  end

  test "does not use a long instruction paragraph as the name before an address" do
    html = <<~HTML
      <p>Der Stempel gibt Auskunft über deine Ankunft auf unserer Anlage. Beim Bezahlen oder Lösen der Angelkarte muss die Zeitstempelkarte vorgelegt werden. Wenn keine Zeitstempelkarte vorgelegt wird, wird eine Anfangszeit ab 6:00 Uhr berechnet.</p>
      <p>Wehldorfer Str. 8<br>27616 Beverstedt</p>
    HTML

    result = ImprintLookup.new("angelteiche-beverstedt.de").send(:extract_fields, html)

    assert_nil result[:buyer_name]
    assert_equal "Wehldorfer Str. 8", result[:buyer_street]
  end

  test "uses homepage details if no usable imprint can be found" do
    lookup = ImprintLookup.new("example.org")
    lookup.define_singleton_method(:fetch_html) do |uri|
      raise ImprintLookup::LookupError, "Nicht gefunden" unless uri.path == "/"

      [ "<p>Beispiel GmbH<br>Musterstraße 1<br>12345 Berlin</p>", uri ]
    end

    assert_equal "Beispiel GmbH", lookup.call[:buyer_name]
  end

  test "extracts company and address from Impressum structured data" do
    html = <<~HTML
      <html><head>
        <script type="application/ld+json">
          {"@type":"Organization","name":"Beispiel GmbH","email":"kontakt@example.org",
           "address":{"@type":"PostalAddress","streetAddress":"Musterstraße 1",
           "postalCode":"12345","addressLocality":"Berlin","addressCountry":"DE"}}
        </script>
      </head><body><h1>Impressum</h1></body></html>
    HTML

    result = ImprintLookup.new("https://example.org/impressum").send(:extract_fields, html)

    assert_equal "Beispiel GmbH", result[:buyer_name]
    assert_equal "kontakt@example.org", result[:buyer_email]
    assert_equal "Musterstraße 1", result[:buyer_street]
    assert_equal "12345", result[:buyer_postal_code]
    assert_equal "Berlin", result[:buyer_city]
    assert_equal "DE", result[:buyer_country]
  end

  test "does not mistake a slogan heading for the company name" do
    html = <<~HTML
      <h2>IT feels good.</h2>
      <h2>Impressum</h2>
      <address>
        Angaben gemäß § 5 DDG<br>
        netactive GmbH<br>
        Barkhausenstraße 6<br>
        27568 Bremerhaven
      </address>
    HTML

    result = ImprintLookup.new("https://example.org/impressum").send(:extract_fields, html)

    assert_equal "netactive GmbH", result[:buyer_name]
    assert_equal "Barkhausenstraße 6", result[:buyer_street]
    assert_equal "27568", result[:buyer_postal_code]
    assert_equal "Bremerhaven", result[:buyer_city]
  end

  test "prefers the visible Impressum email over stale structured data" do
    html = <<~HTML
      <script type="application/ld+json">
        {"@type":"Organization","name":"Beispiel GmbH","email":"kontakt@example.org"}
      </script>
      <address>
        Beispiel GmbH<br>
        Musterstraße 1<br>
        12345 Berlin<br>
        E-Mail: <a href="mailto:info@example.org">info@example.org</a>
      </address>
    HTML

    result = ImprintLookup.new("https://example.org/impressum").send(:extract_fields, html)

    assert_equal "info@example.org", result[:buyer_email]
  end

  test "does not append an adjacent telephone label to a visible Impressum email" do
    html = <<~HTML
      <p>E-Mail-Adresse: info@amrum-clausen.deTelefon: +49 (0) 171 - 3072864</p>
    HTML

    result = ImprintLookup.new("https://example.org/impressum").send(:extract_fields, html)

    assert_equal "info@amrum-clausen.de", result[:buyer_email]
  end

  test "extracts an Impressum encoded in page metadata" do
    html = <<~HTML
      <html>
        <head>
          <title>Impressum - Weser-Ems Perspektiven e.V.</title>
          <meta name="twitter:description" content="Angaben gemäß § 5 TMG: Weser-Ems Perspektiven e. V. Am Klushof 13a 27576 Bremerhaven Vertreten durch: Annelen de Mora info@weser-ems-perspektiven.de">
        </head>
        <body><h1>Impressum</h1></body>
      </html>
    HTML

    result = ImprintLookup.new("https://example.org").send(:extract_fields, html)

    assert_equal "Weser-Ems Perspektiven e. V.", result[:buyer_name]
    assert_equal "Annelen de Mora", result[:buyer_contact_name]
    assert_equal "Am Klushof 13a", result[:buyer_street]
    assert_equal "27576", result[:buyer_postal_code]
    assert_equal "Bremerhaven", result[:buyer_city]
    assert_equal "info@weser-ems-perspektiven.de", result[:buyer_email]
  end

  test "extracts an explicitly named representative from visible association imprint paragraphs" do
    [ "<p>Vertreten durch: Annelen de Mora</p>",
      "<p>Vertreten durch:</p><p>Annelen de Mora<br>Am Klushof 13 a<br>27576 Bremerhaven</p>" ].each do |representation|
      html = <<~HTML
        <p>Weser-Ems Perspektiven e. V.<br>Am Klushof 13a<br>27576 Bremerhaven</p>
        #{representation}
        <p>Registergericht: Amtsgericht Bremen</p>
      HTML

      result = ImprintLookup.new("https://example.org").send(:extract_fields, html)

      assert_equal "Weser-Ems Perspektiven e. V.", result[:buyer_name]
      assert_equal "Annelen de Mora", result[:buyer_contact_name]
      assert_equal "Am Klushof 13a", result[:buyer_street]
    end
  end

  test "keeps a representative address out of the contact name in metadata" do
    html = <<~HTML
      <title>Impressum</title>
      <meta name="description" content="Angaben gemäß § 5 TMG: Beispielverein e. V. Am Klushof 13a 27576 Bremerhaven Vertreten durch: Annelen de Mora Am Klushof 13 a 27576 Bremerhaven info@example.org">
    HTML

    result = ImprintLookup.new("https://example.org").send(:extract_fields, html)

    assert_equal "Annelen de Mora", result[:buyer_contact_name]
  end

  test "prefers the visible Impressum address and separates owner from business name" do
    html = <<~HTML
      <html>
        <head>
          <title>Impressum - Cuxhavener Caravan Center</title>
          <meta name="description" content="Impressum Sascha Kunkel Cuxhavener Caravan Center Op den Dwarsblock 1 27478 Cuxhaven Kontakt Telefon: +49 4723 2534 E-Mail: info@cuxhavener-caravan-center.de">
        </head>
        <body>
          <h1>Impressum</h1>
          <p>Sascha Kunkel<br>Cuxhavener Caravan Center<br>Goethestraße 1<br>27478 Cuxhaven</p>
          <p>Telefon: +49 4723 2534<br>E-Mail: <a href="mailto:info@cuxhavener-caravan-center.de">info@cuxhavener-caravan-center.de</a></p>
        </body>
      </html>
    HTML

    result = ImprintLookup.new("https://example.org").send(:extract_fields, html)

    assert_equal "Cuxhavener Caravan Center", result[:buyer_name]
    assert_equal "Sascha Kunkel", result[:buyer_contact_name]
    assert_equal "Goethestraße 1", result[:buyer_street]
    assert_equal "27478", result[:buyer_postal_code]
    assert_equal "Cuxhaven", result[:buyer_city]
    assert_equal "info@cuxhavener-caravan-center.de", result[:buyer_email]
  end

  test "finds the name in the paragraph immediately before a separate address paragraph" do
    html = <<~HTML
      <html>
        <head><title>Impressum | Psychologische Beratung Natalja Fink-Yazji</title></head>
        <body>
          <h1>Psychologische Beratung Natalja Fink-Yazji</h1>
          <p>Natalja Fink-Yazji</p>
          <p>Charlottenstr. 21<br>74196 Neuenstadt am Kocher</p>
          <p>E-Mail: natalja@example.org</p>
        </body>
      </html>
    HTML

    result = ImprintLookup.new("https://example.org").send(:extract_fields, html)

    assert_equal "Natalja Fink-Yazji", result[:buyer_name]
    assert_equal "Charlottenstr. 21", result[:buyer_street]
    assert_equal "74196", result[:buyer_postal_code]
    assert_equal "Neuenstadt am Kocher", result[:buyer_city]
  end

  test "separates a company and owner in a preceding paragraph" do
    html = <<~HTML
      <html>
        <head><title>Impressum | Kreklau Real Estate</title></head>
        <body>
          <p>Kreklau Real Estate<br>Simone Kreklau<br></p>
          <p>Fehrmoorweg 16 c<br>27578 Bremerhaven</p>
        </body>
      </html>
    HTML

    result = ImprintLookup.new("https://example.org/impressum").send(:extract_fields, html)

    assert_equal "Kreklau Real Estate", result[:buyer_name]
    assert_equal "Simone Kreklau", result[:buyer_contact_name]
    assert_equal "Fehrmoorweg 16 c", result[:buyer_street]
    assert_equal "27578", result[:buyer_postal_code]
    assert_equal "Bremerhaven", result[:buyer_city]
  end

  test "rejects private and non-global network addresses" do
    lookup = ImprintLookup.new("https://example.org")

    assert_not lookup.send(:public_address?, "127.0.0.1")
    assert_not lookup.send(:public_address?, "10.0.0.1")
    assert_not lookup.send(:public_address?, "169.254.169.254")
    assert_not lookup.send(:public_address?, "fd00::1")
    assert lookup.send(:public_address?, "8.8.8.8")
    assert lookup.send(:public_address?, "2001:4860:4860::8888")
  end

  test "rejects non-http schemes and URL credentials" do
    lookup = ImprintLookup.new("https://example.org")

    assert_raises(ImprintLookup::LookupError) { lookup.send(:parse_uri, "file:///etc/passwd") }
    assert_raises(ImprintLookup::LookupError) { lookup.send(:parse_uri, "https://user:pass@example.org/") }
  end

  test "accepts a bare domain and discovers only same-host HTTPS imprint links" do
    lookup = ImprintLookup.new("example.org")
    domain = lookup.send(:parse_domain, "example.org")
    document = Nokogiri::HTML(<<~HTML)
      <a href="/impressum">Impressum</a>
      <a href="https://other.example/impressum">Impressum</a>
      <a href="/kontakt">Kontakt</a>
    HTML

    assert_equal "https://example.org/", domain.to_s
    assert_equal [ "https://example.org/impressum" ], lookup.send(:imprint_links, document, domain).map(&:to_s)
  end

  test "accepts a full Impressum URL while preserving its path and query" do
    lookup = ImprintLookup.new("example.org")

    assert_equal "https://example.org/impressum?lang=de",
      lookup.send(:parse_domain, "https://example.org/impressum?lang=de#contact").to_s
  end

  test "uses www as a fallback while preserving a supplied path" do
    lookup = ImprintLookup.new("pizza-angel.de")
    page = lookup.send(:parse_domain, "pizza-angel.de/impressum?store_id=149")

    assert_equal "https://www.pizza-angel.de/impressum?store_id=149", lookup.send(:www_fallback_uri, page).to_s
    assert_nil lookup.send(:www_fallback_uri, URI("https://www.pizza-angel.de/"))
  end

  test "checks a supplied full page before requesting the domain homepage" do
    lookup = ImprintLookup.new("https://example.org/impressum")
    requested = []
    page = <<~HTML
      <p>Beispiel GmbH<br>Musterstraße 1<br>12345 Berlin</p>
    HTML
    lookup.define_singleton_method(:fetch_homepage) do |uri|
      requested << uri.to_s
      [ page, uri ]
    end
    result = lookup.call

    assert_equal [ "https://example.org/impressum" ], requested
    assert_equal "Beispiel GmbH", result[:buyer_name]
  end

  test "falls back to the domain homepage when the supplied page has no usable details" do
    lookup = ImprintLookup.new("https://example.org/impressum")
    requested = []
    page = "<h1>Impressum</h1>"
    homepage = "<p>Beispiel GmbH<br>Musterstraße 1<br>12345 Berlin</p>"
    lookup.define_singleton_method(:fetch_homepage) do |uri|
      requested << uri.to_s
      [ uri.path == "/impressum" ? page : homepage, uri ]
    end
    result = lookup.call

    assert_equal [ "https://example.org/impressum", "https://example.org/" ], requested
    assert_equal "Beispiel GmbH", result[:buyer_name]
  end

  test "falls back to the domain when the supplied page cannot be fetched" do
    lookup = ImprintLookup.new("https://example.org/kontakt/impressum?lang=de")
    requested = []
    lookup.define_singleton_method(:fetch_homepage) do |uri|
      requested << uri.to_s
      raise ImprintLookup::LookupError, "Seite nicht gefunden" unless uri.path == "/"

      [ "<p>Beispiel GmbH<br>Musterstraße 1<br>12345 Berlin</p>", uri ]
    end

    result = lookup.call

    assert_equal [ "https://example.org/kontakt/impressum?lang=de", "https://example.org/" ], requested
    assert_equal "Beispiel GmbH", result[:buyer_name]
  end

  test "extracts a store-specific Impressum linked from an imprint landing page" do
    html = <<~HTML
      <div class="content store-imprint">
        Pizza Angel<br>
        Schul Str 44<br>
        27749 Delmenhorst<br>
        Jamela Iqbal<br>
        Steuernummer: 57/120/05731<br>
        Telefon: 042215929380
      </div>
    HTML

    result = ImprintLookup.new("https://www.pizza-angel.de/imprint").send(:extract_fields, html)

    assert_equal "Pizza Angel", result[:buyer_name]
    assert_equal "Jamela Iqbal", result[:buyer_contact_name]
    assert_equal "Schul Str 44", result[:buyer_street]
    assert_equal "27749", result[:buyer_postal_code]
    assert_equal "Delmenhorst", result[:buyer_city]
  end

  test "rejects URL credentials and non-HTTPS domains" do
    lookup = ImprintLookup.new("example.org")

    assert_raises(ImprintLookup::LookupError) { lookup.send(:parse_domain, "https://user@example.org/impressum") }
    assert_raises(ImprintLookup::LookupError) { lookup.send(:parse_domain, "http://example.org/impressum") }
  end

  test "prefers the Impressum metadata email over an unrelated footer mailto" do
    html = <<~HTML
      <html>
        <head>
          <title>Impressum - Cuxhavener Caravan Center</title>
          <meta name="description" content="Impressum Sascha Kunkel Cuxhavener Caravan Center Op den Dwarsblock 1 27478 Cuxhaven Kontakt Telefon: +49 4723 2534 E-Mail: info@cuxhavener-caravan-center.de">
        </head>
        <body><footer><a href="mailto:info@cux-caravan.de">info@cux-caravan.de</a></footer></body>
      </html>
    HTML

    result = ImprintLookup.new("https://example.org").send(:extract_fields, html)

    assert_equal "info@cuxhavener-caravan-center.de", result[:buyer_email]
  end
end
