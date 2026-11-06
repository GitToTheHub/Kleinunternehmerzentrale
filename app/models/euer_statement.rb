class EuerStatement < ApplicationRecord
  include EuerDetails
  belongs_to :workspace
  validates :year, inclusion: { in: EuerFields::SOURCES.keys }, uniqueness: { scope: :workspace_id }
end
