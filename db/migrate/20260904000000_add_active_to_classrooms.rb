class AddActiveToClassrooms < ActiveRecord::Migration[7.1]
  def change
    add_column :classrooms, :active, :boolean, default: true, null: false
  end
end
