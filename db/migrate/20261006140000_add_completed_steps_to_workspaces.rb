class AddCompletedStepsToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :completed_steps, :text
  end
end
