class EnforceAnnualTeacherUserInvariants < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :users, <<~SQL.squish, name: "chk_users_annual_fields_by_role"
      (role = 'teacher' AND
        school_year_id IS NOT NULL AND
        login_id IS NOT NULL AND
        school_role IS NOT NULL)
      OR
      (role <> 'teacher' AND
        school_year_id IS NULL AND
        login_id IS NULL AND
        school_role IS NULL AND
        grade IS NULL)
    SQL

    add_check_constraint :users, <<~SQL.squish, name: "chk_users_login_id_canonical"
      login_id IS NULL OR
      (login_id <> '' AND login_id = BTRIM(login_id) AND login_id = LOWER(login_id))
    SQL
  end
end
