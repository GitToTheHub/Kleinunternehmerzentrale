require "test_helper"

class EuerTotalsImportTest < ActiveSupport::TestCase
  def upload(text, encoding: Encoding::UTF_8)
    Struct.new(:data) do
      def size = data.bytesize
      def read(_limit) = data
    end.new(text.encode(encoding))
  end

  test "CSV accepts German amounts UTF8 BOM and Windows encoding with labels" do
    amounts = EuerTotalsImport.csv(upload("\uFEFFPosition;Betrag\nincome_small;\"1.234,56 €\"\nexpense_phone;20,50\nwithdrawals;15,00\n"))
    assert_equal({ "income_small" => "1234.56", "expense_phone" => "20.5", "withdrawals" => "15.0" }, amounts)
    assert_equal({ "expense_meals" => "70.0" }, EuerTotalsImport.csv(upload("Position;Betrag\nGeschäftliche Bewirtung – abziehbarer Anteil;70,00\n", encoding: Encoding::Windows_1252)))
  end

  test "quoted comma delimited amounts and empty template rows work" do
    assert_equal({ "income_small" => "100.0" }, EuerTotalsImport.csv(upload("Position,Betrag\nincome_small,\"100,00\"\n")))
    assert_empty EuerTotalsImport.csv(upload(EuerTotalsImport.template))
    assert_equal "-20.5", EuerTotalsImport.parse_amount("-20,50")
  end

  test "invalid files fail entirely rather than skip unknown duplicate or malformed rows" do
    [ "Position;Betrag\nincome_small;100,00\nUnknown;20,00\n", "Position;Betrag\nincome_small;100\nincome_small;50\n",
      "Position;Betrag\nexpense_phone;1,234\n", "Position;Betrag\nincome_small;\n", "Position;Betrag\nincome_total;19\n",
      "EXTF;700;21\nUmsatz;Soll/Haben-Kennzeichen\n", "Name;Wert\nEinnahmen;100\n" ].each do |text|
      assert_raises(EuerTotalsImport::InvalidFile) { EuerTotalsImport.csv(upload(text)) }
    end
    assert_raises(EuerTotalsImport::InvalidFile) { EuerTotalsImport.csv(upload("x" * (EuerTotalsImport::MAX_BYTES + 1))) }
  end
end
