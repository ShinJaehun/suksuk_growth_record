class CreateStudents < ActiveRecord::Migration[8.1]
  def change
    create_table :students do |t|
      t.references :classroom, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :student_number
      t.boolean :active, null: false, default: true
      t.string :student_pin_digest
      t.string :avatar_key
      t.timestamps
    end

    add_index :students,
              %i[classroom_id student_number],
              unique: true,
              where: "active AND student_number IS NOT NULL",
              name: "index_students_on_active_classroom_number"
    add_check_constraint :students,
                         "student_number IS NULL OR student_number > 0",
                         name: "chk_students_student_number_positive"
  end
end
