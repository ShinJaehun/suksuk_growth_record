class FinalizeClassroomSchoolYearContext < ActiveRecord::Migration[8.1]
  def up
    change_column_null :classrooms, :school_year_id, false
    change_column_null :classrooms, :class_label, false
    add_check_constraint :classrooms,
      "class_label <> '' AND LENGTH(class_label) <= 50 AND " \
        "class_label = BTRIM(class_label) AND RIGHT(class_label, 1) <> '반'",
      name: "chk_classrooms_class_label_canonical"
    add_index :classrooms, %i[school_year_id grade class_label],
      unique: true,
      name: "index_classrooms_on_school_year_grade_class_label"
    remove_reference :classrooms, :school, foreign_key: true
    remove_column :classrooms, :name
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "legacy classroom school and name values cannot be restored"
  end
end
