class AddAnnualTeacherFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :school_year, null: true, foreign_key: true
    add_column :users, :login_id, :string, null: true
    add_column :users, :school_role, :string, null: true
    add_column :users, :grade, :integer, null: true

    add_index :users, %i[school_year_id login_id], unique: true
    add_index :users,
      :school_year_id,
      unique: true,
      where: "role = 'teacher' AND school_role = 'manager' AND school_year_id IS NOT NULL",
      name: "index_users_on_unique_manager_school_year"

    add_check_constraint :users,
      "school_role IS NULL OR school_role IN ('member', 'manager')",
      name: "chk_users_school_role"
    add_check_constraint :users,
      "grade IS NULL OR grade BETWEEN 1 AND 6",
      name: "chk_users_grade_range"
  end
end
