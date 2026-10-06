require "test_helper"

class BackupDatabaseJobTest < ActiveJob::TestCase
  self.use_transactional_tests = false

  test "legt eine Kopie an und behält nur die letzten sieben" do
    dir = Rails.root.join("storage/backups")
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir)
    10.times { |i| FileUtils.touch(dir.join("production-2020010#{i}.sqlite3")) }

    BackupDatabaseJob.perform_now

    files = Dir[dir.join("production-*.sqlite3")]
    assert_equal 7, files.size
    assert_includes files.map { |f| File.basename(f) }, "production-#{Time.current.strftime('%Y%m%d')}.sqlite3"
  ensure
    FileUtils.rm_rf(dir)
  end
end
