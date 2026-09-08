class AddColorKeyToVirtues < ActiveRecord::Migration[8.1]
  def up
    add_column :virtues, :color_key, :string

    # Keep this historical palette independent of application model changes.
    execute <<~SQL
      WITH ordered_virtues AS (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY classroom_id, active ORDER BY position, id) - 1 AS color_position
        FROM virtues
      )
      UPDATE virtues
      SET color_key = CASE (ordered_virtues.color_position % 8)
        WHEN 0 THEN 'blue'
        WHEN 1 THEN 'green'
        WHEN 2 THEN 'violet'
        WHEN 3 THEN 'rose'
        WHEN 4 THEN 'orange'
        WHEN 5 THEN 'teal'
        WHEN 6 THEN 'magenta'
        WHEN 7 THEN 'brown'
      END
      FROM ordered_virtues
      WHERE virtues.id = ordered_virtues.id
    SQL

    change_column_null :virtues, :color_key, false
  end

  def down
    remove_column :virtues, :color_key
  end
end
