class AddSchoolYearAndClassLabelToClassrooms < ActiveRecord::Migration[8.1]
  def up
    add_reference :classrooms, :school_year, null: true, foreign_key: true
    add_column :classrooms, :class_label, :string

    invalid_classroom_id = select_value(<<~SQL.squish)
      WITH normalized AS (
        SELECT classrooms.id,
               classrooms.school_id,
               classrooms.grade,
               CASE
                 WHEN RIGHT(BTRIM(classrooms.name), 1) = '반'
                   THEN BTRIM(LEFT(BTRIM(classrooms.name), LENGTH(BTRIM(classrooms.name)) - 1))
                 ELSE BTRIM(classrooms.name)
               END AS class_label,
               COUNT(school_years.id) FILTER (WHERE school_years.status = 'active') AS active_year_count
        FROM classrooms
        LEFT JOIN school_years ON school_years.school_id = classrooms.school_id
        GROUP BY classrooms.id
      )
      SELECT id
      FROM normalized
      WHERE class_label IS NULL
         OR class_label = ''
         OR RIGHT(class_label, 1) = '반'
         OR LENGTH(class_label) > 50
         OR active_year_count <> 1
      ORDER BY id
      LIMIT 1
    SQL

    if invalid_classroom_id
      raise ActiveRecord::MigrationError,
        "classroom #{invalid_classroom_id} cannot be mapped to a canonical SchoolYear/class label"
    end

    collision_id = select_value(<<~SQL.squish)
      WITH projected AS (
        SELECT classrooms.id,
               school_years.id AS school_year_id,
               classrooms.grade,
               CASE
                 WHEN RIGHT(BTRIM(classrooms.name), 1) = '반'
                   THEN BTRIM(LEFT(BTRIM(classrooms.name), LENGTH(BTRIM(classrooms.name)) - 1))
                 ELSE BTRIM(classrooms.name)
               END AS class_label
        FROM classrooms
        JOIN school_years
          ON school_years.school_id = classrooms.school_id
         AND school_years.status = 'active'
      )
      SELECT MIN(id)
      FROM projected
      GROUP BY school_year_id, grade, class_label
      HAVING COUNT(*) > 1
      LIMIT 1
    SQL

    if collision_id
      raise ActiveRecord::MigrationError,
        "classroom #{collision_id} has a normalized class label collision"
    end

    execute <<~SQL.squish
      UPDATE classrooms
      SET school_year_id = school_years.id,
          class_label = CASE
            WHEN RIGHT(BTRIM(classrooms.name), 1) = '반'
              THEN BTRIM(LEFT(BTRIM(classrooms.name), LENGTH(BTRIM(classrooms.name)) - 1))
            ELSE BTRIM(classrooms.name)
          END
      FROM school_years
      WHERE school_years.school_id = classrooms.school_id
        AND school_years.status = 'active'
    SQL
  end

  def down
    remove_column :classrooms, :class_label
    remove_reference :classrooms, :school_year, foreign_key: true
  end
end
