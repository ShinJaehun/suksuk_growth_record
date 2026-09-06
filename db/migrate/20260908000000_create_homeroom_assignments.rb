class CreateHomeroomAssignments < ActiveRecord::Migration[8.1]
  def up
    create_table :homeroom_assignments do |t|
      t.references :classroom, null: false, foreign_key: true
      t.references :teacher, null: false, foreign_key: { to_table: :users }
      t.date :started_on, null: false
      t.date :ended_on
      t.timestamps
    end

    add_index :homeroom_assignments, :classroom_id,
              unique: true,
              where: 'ended_on IS NULL',
              name: 'index_current_homeroom_assignment_per_classroom'
    add_index :homeroom_assignments, :teacher_id,
              unique: true,
              where: 'ended_on IS NULL',
              name: 'index_current_homeroom_assignment_per_teacher'
    add_check_constraint :homeroom_assignments,
                         'ended_on IS NULL OR ended_on >= started_on',
                         name: 'chk_homeroom_assignment_date_order'

    invalid_classroom_id = select_value(<<~SQL.squish)
      SELECT classrooms.id
      FROM classrooms
      LEFT JOIN users ON users.id = classrooms.teacher_id
      WHERE classrooms.teacher_id IS NOT NULL
        AND (
          users.id IS NULL OR
          users.role <> 'teacher' OR
          users.school_year_id IS DISTINCT FROM classrooms.school_year_id OR
          users.grade IS DISTINCT FROM classrooms.grade
        )
      ORDER BY classrooms.id
      LIMIT 1
    SQL

    if invalid_classroom_id
      raise ActiveRecord::MigrationError,
            "classroom #{invalid_classroom_id} has an invalid legacy teacher assignment"
    end

    duplicate_teacher_id = select_value(<<~SQL.squish)
      SELECT teacher_id
      FROM classrooms
      WHERE teacher_id IS NOT NULL
      GROUP BY teacher_id
      HAVING COUNT(*) > 1
      ORDER BY teacher_id
      LIMIT 1
    SQL

    if duplicate_teacher_id
      raise ActiveRecord::MigrationError,
            "teacher #{duplicate_teacher_id} is assigned to multiple classrooms"
    end

    cutover_date = connection.quote(Date.current)

    execute <<~SQL.squish
      INSERT INTO homeroom_assignments
        (classroom_id, teacher_id, started_on, ended_on, created_at, updated_at)
      SELECT id, teacher_id, #{cutover_date}, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM classrooms
      WHERE teacher_id IS NOT NULL
      ORDER BY id
    SQL
  end

  def down
    drop_table :homeroom_assignments
  end
end
