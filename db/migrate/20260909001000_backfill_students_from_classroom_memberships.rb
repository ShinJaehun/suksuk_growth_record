class BackfillStudentsFromClassroomMemberships < ActiveRecord::Migration[8.1]
  STUDENT_AVATAR_KEYS = (
    (1..23).map { |number| format("boy%02d", number) } +
    (1..17).map { |number| format("girl%02d", number) }
  ).freeze

  def up
    ensure_students_are_empty!
    ensure_relationships_are_valid!
    ensure_no_orphan_student_users!
    ensure_names_are_valid!
    ensure_pins_are_present!
    ensure_student_numbers_are_valid!
    ensure_active_student_numbers_are_unique!
    ensure_active_classroom_limits!
    ensure_avatar_keys_are_valid!
    ensure_no_custom_student_avatars!

    execute <<~SQL.squish
      INSERT INTO students
        (classroom_id, name, student_number, active, student_pin_digest, avatar_key, created_at, updated_at)
      SELECT
        classroom_memberships.classroom_id,
        users.name,
        classroom_memberships.student_number,
        classroom_memberships.status = 'active',
        users.student_pin_digest,
        users.avatar_key,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM classroom_memberships
      INNER JOIN users ON users.id = classroom_memberships.user_id
      WHERE classroom_memberships.role = 'student'
      ORDER BY classroom_memberships.id
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "backfilled students cannot be distinguished safely from other Student rows"
  end

  private

  def ensure_students_are_empty!
    fail_preflight!("students table is not empty") if select_value("SELECT id FROM students LIMIT 1")
  end

  def ensure_relationships_are_valid!
    invalid_id = select_value(<<~SQL.squish)
      SELECT classroom_memberships.id
      FROM classroom_memberships
      LEFT JOIN users ON users.id = classroom_memberships.user_id
      LEFT JOIN classrooms ON classrooms.id = classroom_memberships.classroom_id
      WHERE classroom_memberships.role = 'student'
        AND (users.id IS NULL OR users.role <> 'student' OR classrooms.id IS NULL)
      ORDER BY classroom_memberships.id
      LIMIT 1
    SQL
    fail_preflight!("student membership #{invalid_id} has an invalid relationship") if invalid_id
  end

  def ensure_no_orphan_student_users!
    user_id = select_value(<<~SQL.squish)
      SELECT users.id
      FROM users
      LEFT JOIN classroom_memberships
        ON classroom_memberships.user_id = users.id
        AND classroom_memberships.role = 'student'
      WHERE users.role = 'student'
      GROUP BY users.id
      HAVING COUNT(classroom_memberships.id) = 0
      ORDER BY users.id
      LIMIT 1
    SQL
    fail_preflight!("student User #{user_id} has no student ClassroomMembership") if user_id
  end

  def ensure_names_are_valid!
    user_id = select_value(<<~SQL.squish)
      SELECT users.id
      FROM users
      INNER JOIN classroom_memberships ON classroom_memberships.user_id = users.id
      WHERE classroom_memberships.role = 'student'
        AND (users.name IS NULL OR BTRIM(users.name) = '' OR CHAR_LENGTH(users.name) > 30)
      ORDER BY users.id
      LIMIT 1
    SQL
    fail_preflight!("student User #{user_id} has an invalid name") if user_id
  end

  def ensure_pins_are_present!
    user_id = select_value(<<~SQL.squish)
      SELECT users.id
      FROM users
      INNER JOIN classroom_memberships ON classroom_memberships.user_id = users.id
      WHERE classroom_memberships.role = 'student'
        AND (users.student_pin_digest IS NULL OR BTRIM(users.student_pin_digest) = '')
      ORDER BY users.id
      LIMIT 1
    SQL
    fail_preflight!("student User #{user_id} has no PIN digest") if user_id
  end

  def ensure_student_numbers_are_valid!
    membership_id = select_value(<<~SQL.squish)
      SELECT id
      FROM classroom_memberships
      WHERE role = 'student' AND student_number IS NOT NULL AND student_number < 1
      ORDER BY id
      LIMIT 1
    SQL
    fail_preflight!("student membership #{membership_id} has an invalid student number") if membership_id
  end

  def ensure_active_student_numbers_are_unique!
    classroom_id = select_value(<<~SQL.squish)
      SELECT classroom_id
      FROM classroom_memberships
      WHERE role = 'student' AND status = 'active' AND student_number IS NOT NULL
      GROUP BY classroom_id, student_number
      HAVING COUNT(*) > 1
      ORDER BY classroom_id
      LIMIT 1
    SQL
    fail_preflight!("classroom #{classroom_id} has duplicate active student numbers") if classroom_id
  end

  def ensure_active_classroom_limits!
    classroom_id = select_value(<<~SQL.squish)
      SELECT classroom_id
      FROM classroom_memberships
      WHERE role = 'student' AND status = 'active'
      GROUP BY classroom_id
      HAVING COUNT(*) > 30
      ORDER BY classroom_id
      LIMIT 1
    SQL
    fail_preflight!("classroom #{classroom_id} has more than 30 active students") if classroom_id
  end

  def ensure_avatar_keys_are_valid!
    allowed_keys = STUDENT_AVATAR_KEYS.map { |key| connection.quote(key) }.join(", ")
    user_id = select_value(<<~SQL.squish)
      SELECT users.id
      FROM users
      INNER JOIN classroom_memberships ON classroom_memberships.user_id = users.id
      WHERE classroom_memberships.role = 'student'
        AND users.avatar_key IS NOT NULL
        AND users.avatar_key NOT IN (#{allowed_keys})
      ORDER BY users.id
      LIMIT 1
    SQL
    fail_preflight!("student User #{user_id} has an invalid avatar key") if user_id
  end

  def ensure_no_custom_student_avatars!
    user_id = select_value(<<~SQL.squish)
      SELECT users.id
      FROM users
      INNER JOIN active_storage_attachments
        ON active_storage_attachments.record_type = 'User'
        AND active_storage_attachments.record_id = users.id
        AND active_storage_attachments.name = 'avatar'
      WHERE users.role = 'student'
      ORDER BY users.id
      LIMIT 1
    SQL
    fail_preflight!("student User #{user_id} has a custom avatar attachment") if user_id
  end

  def fail_preflight!(message)
    raise ActiveRecord::MigrationError, "Student backfill preflight failed: #{message}"
  end
end
