# Allocates money in cents while retaining the original order position indexes.
class OrderPositionAllocation
  class Input
    include ActiveModel::Model
    include ActiveModel::Attributes
    include EuroAmounts
    attribute :mode, :string
    attribute :value, :decimal
    euro_amounts :value
    def value_before_type_cast = @attributes["value"].value_before_type_cast

    validates :mode, inclusion: { in: %w[percent amount] }
    validates :value, numericality: { greater_than_or_equal_to: 0 }
  end

  def self.distribute(amount, totals)
    total = totals.sum
    return totals.map { 0.to_d } unless total.positive?
    cents = (amount * 100).round.to_i
    shares = totals.map { |value| cents * value / total }
    rounded = shares.map(&:floor)
    ranking = shares.each_index.sort_by { |i| [ -(shares[i] - rounded[i]), i ] }
    ranking.first(cents - rounded.sum).each { |index| rounded[index] += 1 }
    rounded.map { |value| value.to_d / 100 }
  end

  def self.used(document, totals)
    used = totals.map { 0.to_d }
    return used unless document&.persisted?
    document.active_invoices.select(&:partial_invoice?).each do |invoice|
      allocations = invoice.order_snapshot["allocations"]
      amounts = if allocations.present?
        totals.each_index.map { |index| allocations.find { |item| item["source_index"] == index }&.fetch("amount", "0").to_d }
      else
        distribute(invoice.total, totals)
      end
      used = used.zip(amounts).map { |left, right| left + right }
    end
    used
  end
end
