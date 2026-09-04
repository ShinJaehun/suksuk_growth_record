class EnforceOneManagerPerSchool < ActiveRecord::Migration[8.0]
  INDEX_NAME = "index_school_memberships_on_unique_manager_school"
  MANAGER_ROLE = 10

  def up
    duplicate_school = select_value(<<~SQL.squish)
      SELECT school_id
      FROM school_memberships
      WHERE role = #{MANAGER_ROLE}
      GROUP BY school_id
      HAVING COUNT(*) > 1
      LIMIT 1
    SQL
    if duplicate_school
      raise ActiveRecord::MigrationError, "school #{duplicate_school} has multiple managers"
    end

    add_index :school_memberships,
      :school_id,
      unique: true,
      where: "role = #{MANAGER_ROLE}",
      name: INDEX_NAME
  end

  def down
    remove_index :school_memberships, name: INDEX_NAME
  end
end
