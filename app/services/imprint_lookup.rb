require "ipaddr"
require "cgi"
require "json"
require "net/http"
require "openssl"
require "socket"
require "uri"

class ImprintLookup
  class LookupError < StandardError; end

  MAX_REDIRECTS = 3
  MAX_RESPONSE_BYTES = 1_000_000
  MAX_IMPRINT_LINKS = 5
  MAX_PAGES_TO_CHECK = 10
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5
  COMMON_IMPRINT_PATHS = %w[/impressum /imprint /legal-notice /de/impressum].freeze

  PRIVATE_NETWORKS = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16
    198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    255.255.255.255/32
    2001::/23 2001:db8::/32 2002::/16 3fff::/20
  ].map { |network| IPAddr.new(network) }.freeze
  IPV6_GLOBAL_UNICAST = IPAddr.new("2000::/3")

  def initialize(url)
    @url = url.to_s
  end

  def call
    requested_uri = parse_domain(@url)
    supplied_page = requested_uri.path != "/" || requested_uri.query.present?
    requested_page, requested_page_uri = begin
      fetch_homepage(requested_uri)
    rescue LookupError => error
      requested_error = error
      [ nil, nil ]
    end

    if requested_page
      fields = extract_fields(requested_page)
      return fields if supplied_page && usable_fields?(fields)
    end

    homepage_uri = homepage_uri(requested_page_uri || requested_uri)
    if requested_page && requested_page_uri.path == "/" && requested_page_uri.query.nil?
      homepage = requested_page
      homepage_uri = requested_page_uri
    else
      begin
        homepage, homepage_uri = fetch_homepage(homepage_uri)
      rescue LookupError
        raise requested_error unless requested_page

        homepage = requested_page
        homepage_uri = requested_page_uri
      end
    end

    if homepage != requested_page
      fields = extract_fields(homepage)
      homepage_fields = fields
    end
    homepage_fields ||= fields || {}

    homepage_document = Nokogiri::HTML(homepage)
    candidates = []
    if requested_page
      candidates.concat(imprint_links(Nokogiri::HTML(requested_page), requested_page_uri))
    end
    candidates.concat(imprint_links(homepage_document, homepage_uri))
    candidates.concat(COMMON_IMPRINT_PATHS.map { |path| homepage_uri + path })
    candidates.uniq!
    checked = [ requested_page_uri, homepage_uri ].compact.map(&:to_s)

    until candidates.empty? || checked.length >= MAX_PAGES_TO_CHECK
      imprint_uri = candidates.shift
      next if checked.include?(imprint_uri.to_s)

      checked << imprint_uri.to_s
      begin
        html, final_uri = fetch_html(imprint_uri)
        fields = extract_fields(html)
        return fields if usable_fields?(fields)

        candidates.concat(imprint_links(Nokogiri::HTML(html), final_uri))
        candidates.uniq!
        candidates.reject! { |candidate| checked.include?(candidate.to_s) }
      rescue LookupError
        next
      end
    end

    return homepage_fields if usable_fields?(homepage_fields)

    raise LookupError, "Auf der Domain wurde kein auslesbares Impressum gefunden."
  end

  private

  def usable_fields?(fields)
    fields[:buyer_name].present? && %i[buyer_street buyer_postal_code buyer_city].any? { |field| fields[field].present? }
  end

  def fetch_homepage(uri)
    fetch_html(uri)
  rescue LookupError => error
    fallback_uri = www_fallback_uri(uri)
    raise error unless fallback_uri

    begin
      fetch_html(fallback_uri)
    rescue LookupError
      raise error
    end
  end

  def www_fallback_uri(uri)
    return if uri.host.start_with?("www.")

    URI::HTTPS.build(host: "www.#{uri.host}", path: uri.path.presence || "/", query: uri.query)
  end

  def homepage_uri(uri)
    URI::HTTPS.build(host: uri.host, path: "/")
  end

  def fetch_html(initial_uri)
    uri = initial_uri

    MAX_REDIRECTS.times do |redirect_count|
      response = request(uri)
      if response.is_a?(Net::HTTPRedirection)
        raise LookupError, "Die Webseite leitet zu oft weiter." if redirect_count == MAX_REDIRECTS - 1
        raise LookupError, "Die Weiterleitung enthält keine gültige Adresse." if response["location"].blank?

        redirected_uri = begin
          parse_uri(URI.join(uri, response["location"]).to_s)
        rescue URI::InvalidURIError
          raise LookupError, "Die Weiterleitung enthält keine gültige Adresse."
        end
        if uri.scheme == "https" && redirected_uri.scheme != "https"
          raise LookupError, "Eine Weiterleitung von HTTPS zu HTTP ist nicht erlaubt."
        end
        uri = redirected_uri
        next
      end

      raise LookupError, "Die Webseite konnte nicht abgerufen werden (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)
      raise LookupError, "Die Adresse liefert keine HTML-Seite." unless response["content-type"].to_s.match?(%r{\Atext/html\b}i)

      return [ response.body, uri ]
    end

    raise LookupError, "Die Webseite konnte nicht abgerufen werden."
  rescue Socket::ResolutionError
    raise LookupError, "Die Domain konnte nicht gefunden werden. Prüfe die Schreibweise oder verwende die tatsächlich erreichbare Website-Domain."
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
    raise LookupError, "Die Webseite konnte nicht sicher oder rechtzeitig abgerufen werden. Prüfe, ob die Domain erreichbar ist."
  end

  def parse_domain(value)
    raise LookupError, "Die Webadresse ist zu lang." if value.bytesize > 2_048

    candidate = value.match?(%r{\Ahttps?://}i) ? value : "https://#{value}"
    uri = URI.parse(candidate)
    unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.port == 443
      raise LookupError, "Gib eine öffentliche HTTPS-Domain oder -Adresse ein, zum Beispiel beispiel.de/impressum."
    end

    uri.path = "/" if uri.path.blank?
    uri.fragment = nil
    uri
  rescue URI::InvalidURIError
    raise LookupError, "Die eingegebene Domain ist ungültig."
  end

  def parse_uri(value)
    uri = URI.parse(value)
    unless uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme) && uri.host.present? &&
        uri.userinfo.nil? && uri.port == (uri.scheme == "https" ? 443 : 80)
      raise LookupError, "Das Impressum verweist auf eine ungültige Adresse."
    end

    uri
  rescue URI::InvalidURIError
    raise LookupError, "Das Impressum verweist auf eine ungültige Adresse."
  end

  def imprint_links(document, homepage_uri)
    document.css("a[href]").filter_map do |anchor|
      label = anchor.text
      href = anchor["href"]
      next unless label.match?(/impressum|imprint|legal notice/i) || href.match?(/impressum|imprint|legal-notice/i)

      uri = parse_uri(URI.join(homepage_uri, href).to_s)
      uri if uri.host.casecmp?(homepage_uri.host) && uri.scheme == "https"
    rescue URI::InvalidURIError, LookupError
      next
    end.first(MAX_IMPRINT_LINKS)
  end

  def request(uri)
    addresses = Addrinfo.getaddrinfo(uri.host, uri.port, nil, :STREAM).map(&:ip_address).uniq
    raise LookupError, "Die Adresse verweist nicht auf ein öffentlich erreichbares Ziel." if addresses.empty? || addresses.any? { |address| !public_address?(address) }

    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.ipaddr = addresses.first
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.write_timeout = READ_TIMEOUT if http.respond_to?(:write_timeout=)

    request = Net::HTTP::Get.new(uri.request_uri, "Accept" => "text/html", "Accept-Encoding" => "identity", "User-Agent" => "Kleinunternehmerzentrale/1.0")
    body = +""
    http.start do |connection|
      connection.request(request) do |response|
        response.read_body do |chunk|
          body << chunk
          raise LookupError, "Die Webseite ist zu groß für die automatische Erkennung." if body.bytesize > MAX_RESPONSE_BYTES
        end
        response.body = body
      end
    end
  end

  def public_address?(address)
    ip = IPAddr.new(address)
    if ip.ipv4?
      PRIVATE_NETWORKS.none? { |network| network.ipv4? && network.include?(ip) }
    else
      IPV6_GLOBAL_UNICAST.include?(ip) && PRIVATE_NETWORKS.none? { |network| network.ipv6? && network.include?(ip) }
    end
  rescue IPAddr::InvalidAddressError
    false
  end

  def extract_fields(html)
    document = Nokogiri::HTML(html)
    document.css('script:not([type="application/ld+json"]), style, noscript, svg').remove

    metadata = metadata_address(document)
    structured = structured_organization(document)
    visible = address_from_html(document)
    address = visible.presence || structured[:address].presence || microdata_address(document).presence || metadata
    contact_name = representative_name(document).presence || visible[:contact_name].presence || metadata[:contact_name]
    fields = {
      buyer_name: visible[:name].presence || structured[:name].presence || microdata_value(document, "name") || address[:name],
      buyer_contact_name: plausible_contact_name?(contact_name) ? contact_name : nil,
      buyer_email: imprint_email(document).presence || metadata[:email].presence || mailto_address(document).presence || structured[:email].presence || address[:email],
      buyer_street: address[:street],
      buyer_postal_code: address[:postal_code],
      buyer_city: address[:city],
      buyer_country: address[:country]
    }
    fields.compact_blank.transform_values { |value| value.to_s.squish.truncate(255) }
  end

  def structured_organization(document)
    document.css('script[type="application/ld+json"]').each do |script|
      parsed = JSON.parse(script.text)
      organization = find_organization(parsed)
      next unless organization

      address_data = organization["address"].is_a?(Hash) ? organization["address"] : {}
      return {
        name: organization["name"],
        email: organization["email"],
        address: {
          street: address_data["streetAddress"],
          postal_code: address_data["postalCode"],
          city: address_data["addressLocality"],
          country: country_code(address_data["addressCountry"])
        }.compact_blank
      }
    rescue JSON::ParserError
      next
    end

    {}
  end

  def find_organization(value)
    case value
    when Array
      value.each do |entry|
        found = find_organization(entry)
        return found if found
      end
    when Hash
      types = Array(value["@type"])
      return value if (types & %w[Organization LocalBusiness Corporation]).any?

      value.each_value do |entry|
        found = find_organization(entry)
        return found if found
      end
    end

    nil
  end

  def microdata_address(document)
    node = document.at_css('[itemprop="address"]')
    return unless node

    {
      street: microdata_value(node, "streetAddress"),
      postal_code: microdata_value(node, "postalCode"),
      city: microdata_value(node, "addressLocality"),
      country: country_code(microdata_value(node, "addressCountry"))
    }.compact_blank
  end

  def address_from_html(document)
    nodes = document.css("address, p, .store-imprint")
    nodes.each_with_index do |node, index|
      lines = html_lines(node)
      result = address_from_lines(lines)
      next if result.blank?

      if result[:name].blank?
        previous_lines = html_lines(nodes[index - 1]) if index.positive?
        if previous_lines.present? && plausible_name?(previous_lines.first)
          result[:name] = previous_lines.first
          result[:contact_name] = previous_lines.drop(1).join(" ").presence
        end
      end
      return result
    end
    {}
  end

  def html_lines(node)
    node.inner_html.gsub(%r{<br\s*/?>}i, "\n").then { |html| Nokogiri::HTML.fragment(html).text.lines }
      .map(&:squish).reject(&:blank?)
  end

  def plausible_name?(line)
    line.present? && line.length <= 120 && line.split.length <= 15 &&
      !line.match?(/\A(?:impressum|kontakt|angaben gemäß)\b/i)
  end

  def plausible_contact_name?(line)
    plausible_name?(line) && !line.match?(/[\d:@]/) && country_code(line).nil? &&
      !line.match?(/\A(?:telefon|tel\b|fax|e-?mail|steuer|register|handelsregister|amtsgericht|registergericht|umsatzsteuer|ust[\s.-]?id|vertret)/i)
  end

  def representative_name(document)
    lines = document.css("address, p").flat_map { |node| html_lines(node) }
    lines.each_with_index do |line, index|
      match = line.match(/\AVertreten\s+durch\s*:\s*(.*)\z/i)
      next unless match

      name = match[1].presence || lines[index + 1]
      return name if plausible_contact_name?(name)
    end
    nil
  end

  def address_from_lines(lines)
    postal_line = lines.find { |line| line.match?(/\b\d{5}\s+[\p{L}][\p{L}\s.'’\-]{1,50}/) }
    return {} unless postal_line

    match = postal_line.match(/\A.*?\b(?<postal>\d{5})\s+(?<city>[\p{L}][\p{L}\s.'’\-]{1,50}?)(?:,\s*(?<country>Deutschland|Germany|DE))?\s*\z/i)
    return {} unless match

    line_index = lines.index(postal_line)
    street_index = (line_index - 1).downto(0).find { |index| lines[index].match?(/\d/) }
    return {} unless street_index

    name_lines = lines[0...street_index].select { |line| plausible_name?(line) }
    contact_after_address = lines[(line_index + 1)..]&.find do |line|
      plausible_contact_name?(line)
    end
    {
      name: name_lines.last,
      contact_name: name_lines[0...-1].join(" ").presence || contact_after_address,
      street: lines[street_index],
      postal_code: match[:postal],
      city: match[:city].squish,
      country: country_code(match[:country]) || country_code(lines[line_index + 1])
    }.compact_blank
  end

  def imprint_email(document)
    document.css("address, p").filter_map do |node|
      text = html_lines(node).join(" ")
      next unless text.match?(/e-?mail/i)

      mailto_address(node).presence || email_from_text(text)
    end.first
  end

  def email_from_text(text)
    text[/[\w.+-]+@[\w.-]+\.[a-z]{2,}/i]&.sub(/(?:telefon|tel\.?|fax|handelsregister|registergericht|amtsgericht|umsatzsteuer|ust[.-]?id)\z/i, "")
  end

  def metadata_address(document)
    page_title = [ document.at_css("title")&.text, document.at_css('meta[property="og:title"]')&.[]("content"), document.at_css('meta[name="twitter:title"]')&.[]("content") ].compact.join(" ")
    return {} unless page_title.match?(/impressum|imprint|legal notice/i)

    description = [
      document.at_css('meta[name="description"]')&.[]("content"),
      document.at_css('meta[property="og:description"]')&.[]("content"),
      document.at_css('meta[name="twitter:description"]')&.[]("content")
    ].compact.find { |value| value.match?(/(?:Angaben gemäß|Impressum|Imprint)/i) }
    return {} unless description

    text = CGI.unescapeHTML(description).squish
    email = email_from_text(text)
    legal_address = text.match(/(?:Angaben gemäß[^:]*:\s*)?(?<name>[\p{L}\d&.,'’\-\s]+?\b(?:e\.?\s?V\.?|GmbH|UG(?:\s*\(haftungsbeschränkt\))?|AG|GbR|KG|OHG|eG))\s+(?<street>[\p{L}][\p{L}\s.'’\-]*?\s+\d+\s*[a-z]?)\s+(?<postal>\d{5})\s+(?<city>[\p{L}][\p{L}\s.'’\-]*?)(?=\s+(?:Vertreten|Kontakt|E-Mail|Telefon|Register|Umsatzsteuer|$))/i)
    if legal_address
      fields = metadata_fields(legal_address, email)
      representative = text[/\bVertreten\s+durch\s*:\s*(.+)\z/i, 1]
      if representative
        name = representative.split(/\s+(?=[\w.+-]+@|(?:Kontakt|E-Mail|Telefon|Register)\b|(?:Am|An der|Auf dem|Auf der|Im|In der|Zum|Zur|Op den)\s|[\p{L}.'’\-]+(?:straße|str\.?|weg|platz)\s+\d)/i, 2).first
        fields[:contact_name] = name if plausible_contact_name?(name)
      end
      return fields
    end

    postal_address = text.match(/(?<postal>\d{5})\s+(?<city>[\p{L}][\p{L}\s.'’\-]*?)(?=\s+(?:Vertreten|Kontakt|E-Mail|Telefon|Register|Umsatzsteuer|$))/i)
    return { email: email }.compact_blank unless postal_address

    prefix = text[0...postal_address.begin(:postal)]
    street_match = prefix.match(/(?<street>\b(?:Am|An der|Auf dem|Auf der|Im|In der|Zum|Zur|Op den)\s+[\p{L}\d\s.'’\-]+?\s+\d+\s*[a-z]?)\s*\z/i)
    return { email: email }.compact_blank unless street_match

    name = prefix[0...street_match.begin(:street)].sub(/\A.*?(?:Angaben gemäß[^:]*:\s*)/i, "").sub(/\AImpressum\s*/i, "").squish
    {
      name: name.presence,
      email: email,
      street: street_match[:street].squish,
      postal_code: postal_address[:postal],
      city: postal_address[:city].squish
    }.compact_blank
  end

  def metadata_fields(address_match, email)
    {
      name: address_match[:name].squish,
      email: email,
      street: address_match[:street].squish,
      postal_code: address_match[:postal],
      city: address_match[:city].squish
    }.compact_blank
  end

  def microdata_value(document, property)
    document.at_css("[itemprop='#{property}']")&.[]("content").presence ||
      document.at_css("[itemprop='#{property}']")&.text&.squish
  end

  def mailto_address(document)
    href = document.at_css('a[href^="mailto:"]')&.[]("href")
    href&.delete_prefix("mailto:")&.split("?")&.first
  end

  def country_code(country)
    value = country.to_s.squish
    return if value.blank?
    return "DE" if value.match?(/\A(de|deutschland|germany)\z/i)

    Invoice::COUNTRIES.find { |name, code| name.casecmp?(value) || code.casecmp?(value) }&.last
  end
end
