class DropSchoolMemberships < ActiveRecord::Migration[8.1]
  def up
    mismatched_id = select_value(<<~SQL.squish)
      SELECT school_memberships.id
      FROM school_memberships
      LEFT JOIN users ON users.id = school_memberships.user_id
      LEFT JOIN school_years ON school_years.id = users.school_year_id
      WHERE users.id IS NULL
         OR users.role <> 'teacher'
         OR school_years.id IS NULL
         OR school_memberships.school_id <> school_years.school_id
         OR CASE school_memberships.role
              WHEN 0 THEN 'member'
              WHEN 10 THEN 'manager'
            END IS DISTINCT FROM users.school_role
         OR school_memberships.grade IS DISTINCT FROM users.grade
      ORDER BY school_memberships.id
      LIMIT 1
    SQL

    if mismatched_id
      raise ActiveRecord::MigrationError,
        "school membership #{mismatched_id} does not match annual teacher authority"
    end

    drop_table :school_memberships
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "school membership compatibility data cannot be restored"
  end
end
