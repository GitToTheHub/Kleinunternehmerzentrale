# Run against the local app: ruby test/browser/e_invoice_viewer_check.rb
require "selenium-webdriver"
require "tmpdir"
require "zlib"
require "json"

# Minimal PDF with an actual compressed embedded XML stream. No user data or DB writes.
def pdf_with_attachments(xmls)
  objects = [ nil, "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << >> >>" ]
  files = xmls.map.with_index do |xml, index|
    stream = Zlib::Deflate.deflate(xml)
    stream_id = objects.length
    objects << "<< /Type /EmbeddedFile /Subtype /text#2Fxml /Filter /FlateDecode /Length #{stream.bytesize} >>\nstream\n".b + stream + "\nendstream"
    spec_id = objects.length
    objects << "<< /Type /Filespec /F (factur-x-#{index}.xml) /UF (factur-x-#{index}.xml) /AFRelationship /Data /EF << /F #{stream_id} 0 R >> >>"
    "(factur-x-#{index}.xml) #{spec_id} 0 R"
  end
  objects[1] = "<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles << /Names [#{files.join(' ')}] >> >> >>" unless files.empty?
  pdf = "%PDF-1.7\n".b
  offsets = [ 0 ]
  objects.each_with_index do |object, index|
    next if index.zero?
    offsets << pdf.bytesize
    pdf << "#{index} 0 obj\n" << object.b << "\nendobj\n"
  end
  xref = pdf.bytesize
  pdf << "xref\n0 #{objects.length}\n0000000000 65535 f \n"
  offsets.drop(1).each { |offset| pdf << format("%010d 00000 n \n", offset) }
  pdf << "trailer\n<< /Size #{objects.length} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
end

Selenium::WebDriver.logger.level = :warn
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument("--headless")
options.add_argument("--window-size=1400,1100")
options.add_option("goog:loggingPrefs", { performance: "ALL", browser: "ALL" })
driver = Selenium::WebDriver.for(:chrome, options: options)
wait = Selenium::WebDriver::Wait.new(timeout: 30)
base = ENV.fetch("VIEWER_BASE_URL", "http://127.0.0.1:3000")
fixtures = File.expand_path("../fixtures/files", __dir__)
begin
  driver.get("#{base}/e-rechnungsviewer")
  wait.until { driver.find_elements(css: '[data-e-invoice-viewer-target="file"]').any? }
  load_file = lambda do |path, expected, error = false|
    driver.find_element(id: "e-invoice-file").send_keys(path)
    selector = error ? '[data-e-invoice-viewer-target="error"]' : '[data-e-invoice-viewer-target="result"]'
    wait.until do
      failure = driver.find_element(css: '[data-e-invoice-viewer-target="error"]')
      raise "Viewer: #{failure.text}" if !error && failure.displayed?
      node = driver.find_element(css: selector)
      node.displayed? && node.text.include?(expected)
    end
  end
  ubl = File.read("#{fixtures}/viewer_ubl.xml")
  cii = File.read("#{fixtures}/viewer_cii.xml")

  # Test real DOM XML parsing, including namespace changes and credit notes.
  result = driver.execute_async_script(<<~JS, ubl, cii)
    const [ubl,cii,done]=arguments;
    import('e_invoice').then(({parseInvoiceXml})=>{
      const invoice=parseInvoiceXml(ubl), other=parseInvoiceXml(cii);
      const credit=parseInvoiceXml(ubl.replaceAll('Invoice-2','CreditNote-2').replaceAll('InvoiceLine','CreditNoteLine').replaceAll('InvoicedQuantity','CreditedQuantity').replace(/<Invoice /,'<CreditNote ').replace('</Invoice>','</CreditNote>'));
      const prefix=parseInvoiceXml(cii.replaceAll('ram:','data:').replace('xmlns:ram=','xmlns:data='));
      const failures=['<broken>', '<Invoice/>', '<!DOCTYPE x [<!ENTITY a "data">]>'+ubl];
      done({number:invoice.number,due:invoice.due,net:invoice.lines[0].net,tax:invoice.taxes[0].rate,payable:invoice.totals.at(-1)[1],order:invoice.references[1][1],cii:other.number,ciiNet:other.lines[0].net,credit:credit.type,prefix:prefix.seller.name,rejected:failures.every(xml=>{try{parseInvoiceXml(xml);return false}catch{return true}})});
    }).catch(error=>done({error:error.message}));
  JS
  expected = { "number"=>"TEST-UBL-42", "due"=>"2026-10-21", "net"=>"100.00", "tax"=>"19", "payable"=>"87.10", "order"=>"BESTELLUNG-42", "cii"=>"TEST-CII-7", "ciiNet"=>"360.00", "credit"=>"Gutschrift", "prefix"=>"Teststudio", "rejected"=>true }
  raise "Parser: #{result}" unless result == expected
  puts "Parser: UBL, CII, credit note, alternate prefixes, tax and totals, invalid XML and DTD rejection passed"

  load_file.call("#{fixtures}/viewer_ubl.xml", "TEST-UBL-42")
  text = driver.find_element(css: '[data-e-invoice-viewer-target="result"]').text
  [ "Testbetrieb Müller", "Testkunde GmbH", "07.10.2026", "21.10.2026", "87,10", "DE89370400440532013000", "Treuerabatt", "<img src=x onerror=alert(1)>" ].each { |value| raise "Missing #{value}" unless text.include?(value) }
  raise "Uploaded markup executed" if driver.find_elements(css: ".e-invoice-viewer__document img, .e-invoice-viewer__document script").any?
  puts "UBL upload: names, dates, line items, discounts, payable balance and payment data shown; markup stays text"

  Dir.mktmpdir("e-invoice-viewer-") do |directory|
    pdf = "#{directory}/zugferd.pdf"
    File.binwrite(pdf, pdf_with_attachments([ cii ]))
    load_file.call(pdf, "TEST-CII-7")
    raise "Missing tax exemption" unless driver.find_element(css: '[data-e-invoice-viewer-target="result"]').text.include?("§ 19 UStG")
    puts "PDF: embedded compressed CII invoice extracted and displayed locally"

    [ "light", "dark" ].each do |theme|
      driver.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      wait.until { driver.execute_script("return getComputedStyle(document.querySelector('.button--secondary')).backgroundColor === getComputedStyle(document.querySelector('.e-invoice-viewer__document')).backgroundColor") }
      [ 1400, 390 ].each do |width|
        driver.manage.window.resize_to(width, 1100)
        raise "Horizontal page overflow at #{width}" if driver.execute_script("return document.documentElement.scrollWidth > innerWidth")
        driver.save_screenshot("/private/tmp/e-invoice-viewer-#{theme}-#{width}.png")
        driver.execute_script("document.querySelector('.e-invoice-viewer__document').scrollIntoView({block:'start',behavior:'instant'})")
        driver.save_screenshot("/private/tmp/e-invoice-viewer-document-#{theme}-#{width}.png")
        driver.execute_script("window.scrollTo({top:0,behavior:'instant'})")
      end
    end
    driver.execute_cdp("Emulation.setEmulatedMedia", media: "print")
    raise "File controls print" if driver.find_element(id: "e-invoice-file").displayed?
    raise "Invoice missing in print" unless driver.find_element(css: '[data-e-invoice-viewer-target="result"]').displayed?
    driver.execute_cdp("Emulation.setEmulatedMedia", media: "screen")
    puts "Layout: light/dark mode, desktop/mobile and print verified"

    File.binwrite("#{directory}/normal.pdf", pdf_with_attachments([]))
    load_file.call("#{directory}/normal.pdf", "keine eingebettete E-Rechnung", true)
    raise "Old result remains visible" if driver.find_element(css: '[data-e-invoice-viewer-target="result"]').displayed?
    File.binwrite("#{directory}/ambiguous.pdf", pdf_with_attachments([ cii, ubl ]))
    load_file.call("#{directory}/ambiguous.pdf", "mehrere XML-Rechnungen", true)
    File.write("#{directory}/broken.xml", "<broken>")
    load_file.call("#{directory}/broken.xml", "beschädigt", true)
    load_file.call("#{fixtures}/viewer_cii.xml", "TEST-CII-7")
  end
  driver.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
  raise "Private invoice cached" if driver.find_element(css: '[data-e-invoice-viewer-target="result"]').displayed?
  raise "Private invoice text cached" unless driver.find_element(css: '[data-e-invoice-viewer-target="result"]').attribute("textContent").empty?
  requests = driver.logs.get(:performance).filter_map do |log|
    message = JSON.parse(log.message).fetch("message")
    message.dig("params", "request") if message["method"] == "Network.requestWillBeSent"
  end
  raise "Unexpected network transfer" unless requests.all? { |request| request["method"] == "GET" && (request["url"].start_with?(base) || request["url"].start_with?("data:", "blob:")) }
  errors = driver.logs.get(:browser).select { |log| log.level == "SEVERE" }
  raise "Browser errors: #{errors.map(&:message)}" unless errors.empty?
  puts "Failures and privacy: ordinary/ambiguous PDFs and broken XML handled; no upload, no external requests, no invoice in Turbo cache"
rescue StandardError
  driver.save_screenshot("/private/tmp/e-invoice-viewer-failure.png")
  warn driver.logs.get(:browser).map(&:message).join("\n")
  raise
ensure
  driver.quit
end
