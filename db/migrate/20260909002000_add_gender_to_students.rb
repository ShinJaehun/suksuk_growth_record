class AddGenderToStudents < ActiveRecord::Migration[8.1]
  def up
    add_column :students, :gender, :string

    ambiguous_student_id = select_value(<<~SQL.squish)
      SELECT students.id
      FROM students
      INNER JOIN classroom_memberships
        ON classroom_memberships.classroom_id = students.classroom_id
        AND classroom_memberships.role = 'student'
        AND classroom_memberships.student_number IS NOT DISTINCT FROM students.student_number
        AND (classroom_memberships.status = 'active') = students.active
      INNER JOIN users
        ON users.id = classroom_memberships.user_id
        AND users.name = students.name
        AND users.student_pin_digest = students.student_pin_digest
        AND users.avatar_key IS NOT DISTINCT FROM students.avatar_key
      GROUP BY students.id
      HAVING COUNT(users.id) > 1
      ORDER BY students.id
      LIMIT 1
    SQL
    fail_migration!("Student #{ambiguous_student_id} matches multiple legacy student Users") if ambiguous_student_id

    invalid_user_id = select_value(<<~SQL.squish)
      SELECT users.id
      FROM users
      INNER JOIN classroom_memberships ON classroom_memberships.user_id = users.id
      WHERE classroom_memberships.role = 'student'
        AND users.gender IS NOT NULL
        AND users.gender NOT IN ('boy', 'girl')
      ORDER BY users.id
      LIMIT 1
    SQL
    fail_migration!("student User #{invalid_user_id} has an invalid gender") if invalid_user_id

    execute <<~SQL.squish
      UPDATE students
      SET gender = users.gender
      FROM classroom_memberships
      INNER JOIN users ON users.id = classroom_memberships.user_id
      WHERE classroom_memberships.classroom_id = students.classroom_id
        AND classroom_memberships.role = 'student'
        AND classroom_memberships.student_number IS NOT DISTINCT FROM students.student_number
        AND (classroom_memberships.status = 'active') = students.active
        AND users.name = students.name
        AND users.student_pin_digest = students.student_pin_digest
        AND users.avatar_key IS NOT DISTINCT FROM students.avatar_key
    SQL

    execute <<~SQL.squish
      UPDATE students
      SET gender = 'boy'
      WHERE gender IS NULL
        AND avatar_key LIKE 'boy%'
        AND NOT EXISTS (
          SELECT 1
          FROM classroom_memberships
          INNER JOIN users ON users.id = classroom_memberships.user_id
          WHERE classroom_memberships.classroom_id = students.classroom_id
            AND classroom_memberships.role = 'student'
            AND classroom_memberships.student_number IS NOT DISTINCT FROM students.student_number
            AND (classroom_memberships.status = 'active') = students.active
            AND users.name = students.name
            AND users.student_pin_digest = students.student_pin_digest
            AND users.avatar_key IS NOT DISTINCT FROM students.avatar_key
        )
    SQL

    execute <<~SQL.squish
      UPDATE students
      SET gender = 'girl'
      WHERE gender IS NULL
        AND avatar_key LIKE 'girl%'
        AND NOT EXISTS (
          SELECT 1
          FROM classroom_memberships
          INNER JOIN users ON users.id = classroom_memberships.user_id
          WHERE classroom_memberships.classroom_id = students.classroom_id
            AND classroom_memberships.role = 'student'
            AND classroom_memberships.student_number IS NOT DISTINCT FROM students.student_number
            AND (classroom_memberships.status = 'active') = students.active
            AND users.name = students.name
            AND users.student_pin_digest = students.student_pin_digest
            AND users.avatar_key IS NOT DISTINCT FROM students.avatar_key
        )
    SQL

    add_check_constraint :students,
                         "gender IS NULL OR gender IN ('boy', 'girl')",
                         name: "chk_students_gender"
  end

  def down
    remove_check_constraint :students, name: "chk_students_gender"
    remove_column :students, :gender
  end

  private

  def fail_migration!(message)
    raise ActiveRecord::MigrationError, "Student gender migration failed: #{message}"
  end
end
