class MigrateTeacherAssignmentsToClassrooms < ActiveRecord::Migration[8.0]
  class Membership < ActiveRecord::Base
    self.table_name = "classroom_memberships"
  end

  def up
    verify_teacher_assignments!
    backfill_membership_grades!

    add_reference :classrooms, :teacher, null: true, foreign_key: { to_table: :users }, index: false
    add_index :classrooms, :teacher_id, unique: true, where: "teacher_id IS NOT NULL"

    execute <<~SQL.squish
      UPDATE classrooms
      SET teacher_id = classroom_memberships.user_id
      FROM classroom_memberships
      WHERE classroom_memberships.classroom_id = classrooms.id
        AND classroom_memberships.role = 'teacher'
    SQL

    Membership.where(role: "teacher").delete_all
  end

  def down
    duplicate_pair = select_value(<<~SQL.squish)
      SELECT 1
      FROM classrooms
      INNER JOIN classroom_memberships
        ON classroom_memberships.classroom_id = classrooms.id
       AND classroom_memberships.user_id = classrooms.teacher_id
      WHERE classrooms.teacher_id IS NOT NULL
      LIMIT 1
    SQL
    raise ActiveRecord::MigrationError, "teacher membership already exists for a classroom assignment" if duplicate_pair

    execute <<~SQL.squish
      INSERT INTO classroom_memberships
        (classroom_id, user_id, role, status, created_at, updated_at)
      SELECT id, teacher_id, 'teacher', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM classrooms
      WHERE teacher_id IS NOT NULL
    SQL

    remove_reference :classrooms, :teacher, foreign_key: { to_table: :users }, index: false
  end

  private

  def verify_teacher_assignments!
    fail_if_present!(<<~SQL.squish, "a teacher is assigned to multiple classrooms")
      SELECT user_id FROM classroom_memberships
      WHERE role = 'teacher'
      GROUP BY user_id HAVING COUNT(DISTINCT classroom_id) > 1
    SQL
    fail_if_present!(<<~SQL.squish, "a classroom has multiple teachers")
      SELECT classroom_id FROM classroom_memberships
      WHERE role = 'teacher'
      GROUP BY classroom_id HAVING COUNT(DISTINCT user_id) > 1
    SQL
    fail_if_present!(<<~SQL.squish, "a teacher assignment has no school membership")
      SELECT classroom_memberships.id
      FROM classroom_memberships
      LEFT JOIN school_memberships ON school_memberships.user_id = classroom_memberships.user_id
      WHERE classroom_memberships.role = 'teacher' AND school_memberships.id IS NULL
    SQL
    fail_if_present!(<<~SQL.squish, "a teacher assignment crosses schools")
      SELECT classroom_memberships.id
      FROM classroom_memberships
      INNER JOIN classrooms ON classrooms.id = classroom_memberships.classroom_id
      INNER JOIN school_memberships ON school_memberships.user_id = classroom_memberships.user_id
      WHERE classroom_memberships.role = 'teacher'
        AND school_memberships.school_id <> classrooms.school_id
    SQL
    fail_if_present!(<<~SQL.squish, "a teacher assignment has a conflicting grade")
      SELECT classroom_memberships.id
      FROM classroom_memberships
      INNER JOIN classrooms ON classrooms.id = classroom_memberships.classroom_id
      INNER JOIN school_memberships ON school_memberships.user_id = classroom_memberships.user_id
      WHERE classroom_memberships.role = 'teacher'
        AND school_memberships.grade IS NOT NULL
        AND school_memberships.grade <> classrooms.grade
    SQL
  end

  def backfill_membership_grades!
    execute <<~SQL.squish
      UPDATE school_memberships
      SET grade = classrooms.grade, updated_at = CURRENT_TIMESTAMP
      FROM classroom_memberships
      INNER JOIN classrooms ON classrooms.id = classroom_memberships.classroom_id
      WHERE classroom_memberships.role = 'teacher'
        AND school_memberships.user_id = classroom_memberships.user_id
        AND school_memberships.grade IS NULL
    SQL
  end

  def fail_if_present!(sql, message)
    raise ActiveRecord::MigrationError, message if select_value("SELECT 1 FROM (#{sql}) conflicts LIMIT 1")
  end
end
