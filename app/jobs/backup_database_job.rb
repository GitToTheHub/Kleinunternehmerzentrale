# Legt täglich eine konsistente Kopie der Hauptdatenbank an und behält die letzten 7.
class BackupDatabaseJob < ApplicationJob
  KEEP = 7

  def perform
    dir = Rails.root.join("storage/backups")
    FileUtils.mkdir_p(dir)
    target = dir.join("production-#{Time.current.strftime('%Y%m%d')}.sqlite3")
    FileUtils.rm_f(target)
    ActiveRecord::Base.connection.execute("VACUUM INTO #{ActiveRecord::Base.connection.quote(target.to_s)}")
    Dir[dir.join("production-*.sqlite3")].sort.reverse.drop(KEEP).each { |old| File.delete(old) }
  end
end
