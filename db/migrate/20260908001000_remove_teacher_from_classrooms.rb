class RemoveTeacherFromClassrooms < ActiveRecord::Migration[8.1]
  def up
    remove_index :classrooms, name: "index_classrooms_on_teacher_id"
    remove_reference :classrooms, :teacher,
      foreign_key: { to_table: :users },
      index: false
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "classrooms.teacher_id cannot represent HomeroomAssignment history"
  end
end
