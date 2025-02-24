class AddWinnerRemoveRankToTeams < ActiveRecord::Migration[7.0]
  def change
    add_column :teams, :winner, :boolean
    remove_column :teams, :rank, :integer
  end
end
