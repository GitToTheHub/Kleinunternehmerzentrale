class InvoiceDraft < ApplicationRecord
  belongs_to :workspace
  enum :status, { active: "active", discarded: "discarded", completed: "completed" }
  before_validation { self.form_token ||= SecureRandom.uuid }
  validates :form_token, presence: true
  validates :data, exclusion: { in: [ nil ] }

  # Keep the identifier to reject late autosaves, while removing the draft's contents.
  def close!(status)
    update!(status: status, data: {})
  end
end
