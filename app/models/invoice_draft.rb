class InvoiceDraft < ApplicationRecord
  RESUME_SECTIONS = %w[invoice-step-seller invoice-step-buyer invoice-step-dates invoice-step-lines].freeze

  belongs_to :workspace
  enum :status, { active: "active", discarded: "discarded", completed: "completed" }
  before_validation { self.form_token ||= SecureRandom.uuid }
  validates :resume_section, inclusion: { in: RESUME_SECTIONS }, allow_nil: true
  validates :form_token, presence: true
  validates :data, exclusion: { in: [ nil ] }

  # Keep the identifier to reject late autosaves, while removing the draft's contents.
  def close!(status)
    update!(status: status, data: {}, resume_section: nil)
  end
end
