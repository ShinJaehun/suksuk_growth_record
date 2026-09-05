class CreateSchoolYears < ActiveRecord::Migration[8.1]
  def change
    create_table :school_years do |t|
      t.references :school, null: false, foreign_key: true
      t.integer :year, null: false
      t.string :status, null: false, default: 'planning'

      t.timestamps

      t.index %i[school_id year], unique: true
      t.index :school_id,
              unique: true,
              where: "status = 'active'",
              name: 'index_school_years_on_unique_active_school'
      t.index :school_id,
              unique: true,
              where: "status = 'planning'",
              name: 'index_school_years_on_unique_planning_school'
    end

    add_check_constraint :school_years,
                         'year BETWEEN 1000 AND 9999',
                         name: 'chk_school_years_year_range'
    add_check_constraint :school_years,
                         "status IN ('planning', 'active', 'archived')",
                         name: 'chk_school_years_status'
  end
end
