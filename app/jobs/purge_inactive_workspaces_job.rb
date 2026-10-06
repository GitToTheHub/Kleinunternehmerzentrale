# Löscht Gast-Bereiche, die seit drei Monaten nicht benutzt wurden.
class PurgeInactiveWorkspacesJob < ApplicationJob
  queue_as :default

  def perform
    Workspace.purge_expired_guests
  end
end
