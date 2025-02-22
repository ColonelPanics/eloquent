class AddScoresToResults < ActiveRecord::Migration[7.0]
  def change
    add_column :results, :for, :integer
    add_column :results, :against, :integer
  end
end
