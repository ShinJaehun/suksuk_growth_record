class FinalizeLegacyStudentSchemaCleanup < ActiveRecord::Migration[8.1]
  def up
    drop_table :classroom_memberships

    remove_column :users, :student_pin_digest, :string
    change_column_default :users, :role, from: "student", to: nil

    add_check_constraint :users,
                         "role IN ('teacher', 'admin')",
                         name: "chk_users_role"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "legacy student User and ClassroomMembership data are intentionally discarded"
  end
end
