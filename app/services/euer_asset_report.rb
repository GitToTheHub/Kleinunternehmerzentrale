class EuerAssetReport
  # The AVEÜR lines and field numbers are identical in the 2025 and 2026 forms.
  GROUPS = {
    "land" => [ [ :historical_cost, 4, 100 ], [ :opening, 5, 101 ], [ :additions, 6, 102 ], [ :residual, 7, 105 ], [ :closing, 8, 106 ] ],
    "building" => [ [ :historical_cost, 9, 110 ], [ :opening, 10, 111 ], [ :additions, 11, 112 ], [ :special, 12, 113 ], [ :ordinary, 13, 114 ], [ :residual, 14, 115 ], [ :closing, 15, 116 ] ],
    "intangible" => [ [ :historical_cost, 34, 320 ], [ :opening, 35, 321 ], [ :additions, 36, 322 ], [ :ordinary, 37, 324 ], [ :residual, 38, 325 ], [ :closing, 39, 326 ] ],
    "vehicle" => [ [ :historical_cost, 40, 400 ], [ :opening, 41, 401 ], [ :additions, 42, 402 ], [ :special, 43, 403 ], [ :ordinary, 44, 404 ], [ :residual, 45, 405 ], [ :closing, 46, 406 ] ],
    "office" => [ [ :historical_cost, 48, 410 ], [ :opening, 49, 411 ], [ :additions, 50, 412 ], [ :special, 51, 413 ], [ :ordinary, 52, 414 ], [ :residual, 53, 415 ], [ :closing, 54, 416 ] ],
    "movable" => [ [ :historical_cost, 55, 420 ], [ :opening, 56, 421 ], [ :additions, 57, 422 ], [ :special, 58, 423 ], [ :ordinary, 59, 424 ], [ :residual, 60, 425 ], [ :closing, 61, 426 ] ]
  }.freeze
  LABELS = { historical_cost: "Historische Anschaffungs- / Einlagewerte des Anfangsbestands", opening: "Buchwerte zu Jahresbeginn", additions: "Zugänge",
             ordinary: "Abschreibung", special: "Sonderabschreibung", residual: "Restbuchwerte der Abgänge", closing: "Buchwerte zum Jahresende" }.freeze

  def initialize(report)
    @report = report
  end

  def rows
    @report.asset_rows.reject { |asset, _| asset.depreciation_method == "gwg" }.group_by { |asset, _| asset.category }.flat_map do |category, assets|
      GROUPS.fetch(category).map do |metric, line, number|
        amount = assets.sum do |asset, schedule|
          metric == :historical_cost ? (asset.acquired_on.year < @report.year ? asset.cost : 0.to_d) : schedule.fetch(metric)
        end
        { group: BusinessAsset::CATEGORIES.fetch(category), label: LABELS.fetch(metric), line: EuerFields.supported?(@report.year) ? line : nil,
          number: EuerFields.supported?(@report.year) ? number : nil, amount: amount }
      end
    end
  end
end
