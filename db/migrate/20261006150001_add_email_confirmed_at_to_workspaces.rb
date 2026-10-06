class AddEmailConfirmedAtToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :email_confirmed_at, :datetime
  end
end
