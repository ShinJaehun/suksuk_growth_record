class AddTeacherCredentialFoundation < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_change_required, :boolean, null: false, default: false

    create_table :teacher_credential_events do |t|
      t.references :actor_user, null: false, foreign_key: { to_table: :users }
      t.references :teacher_user, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.timestamps

      t.check_constraint "action IN ('temporary_password_issued', 'temporary_password_reissued')",
        name: "chk_teacher_credential_events_action"
    end
  end
end
