require "test_helper"

class InvoiceLineLinksTest < ActiveSupport::TestCase
  test "Links behalten Zieladressen in Klartext und oeffnen separat" do
    line = InvoiceLine.new(details: '<p>Siehe <a href="https://example.de/projekt?a=1&amp;b=2"><strong>Projektwebsite</strong></a>.</p>')
    assert_equal "Siehe Projektwebsite (https://example.de/projekt?a=1&b=2).", line.details_text
    link = Nokogiri::HTML.fragment(line.details_html).at_css("a")
    assert_equal "https://example.de/projekt?a=1&b=2", link["href"]
    assert_equal "_blank", link["target"]
    assert_equal "noopener noreferrer", link["rel"]
  end

  test "sichtbare Adressen werden nicht verdoppelt und Listen bleiben lesbar" do
    line = InvoiceLine.new(details: '<ul><li><a href="https://example.de">https://example.de</a></li><li><a href="mailto:kontakt@example.de">Kontakt</a></li></ul>')
    assert_equal "- https://example.de\n- Kontakt (mailto:kontakt@example.de)", line.details_text
  end

  test "gefaehrliche Linkziele und fremde Attribute werden entfernt" do
    line = InvoiceLine.new(details: '<p><a href="javascript:alert(1)" onclick="alert(1)" target="_top">Unsicher</a> <a href="https://example.de" onclick="x()">Sicher</a></p>')
    line.valid?
    assert_no_match(/javascript|onclick|_top/, line.details)
    assert_equal "Unsicher Sicher (https://example.de)", line.details_text
  end
  test "Nummerierung und Einrueckung bleiben im Klartext erhalten" do
    line = InvoiceLine.new(details: '<ol><li>Erster Punkt<ul><li>Unterpunkt <a href="https://example.de">Link</a></li><li>Noch einer</li></ul></li><li>Zweiter Punkt<ol><li>Tiefer</li></ol></li></ol>')
    assert_equal "1. Erster Punkt\n  - Unterpunkt Link (https://example.de)\n  - Noch einer\n2. Zweiter Punkt\n  1. Tiefer", line.details_text
  end
end
