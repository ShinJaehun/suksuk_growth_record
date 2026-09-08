class CreateDailyVirtueConfigurations < ActiveRecord::Migration[8.1]
  def up
    execute "LOCK TABLE daily_growth_records, daily_growth_scores, virtues IN SHARE ROW EXCLUSIVE MODE"
    verify_legacy_compositions!

    create_table :daily_virtue_configurations do |t|
      t.references :classroom, null: false, foreign_key: true
      t.date :recorded_on, null: false
      t.timestamps
    end
    add_index :daily_virtue_configurations, %i[classroom_id recorded_on],
      unique: true, name: "index_daily_configurations_on_classroom_and_date"
    add_index :daily_virtue_configurations, %i[id classroom_id recorded_on],
      unique: true, name: "index_daily_configurations_on_record_identity"

    create_table :daily_virtue_configuration_items do |t|
      t.references :daily_virtue_configuration, null: false, foreign_key: true,
        index: { name: "index_daily_configuration_items_on_configuration" }
      t.references :virtue, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false
      t.timestamps
    end
    add_index :daily_virtue_configuration_items, %i[daily_virtue_configuration_id virtue_id],
      unique: true, name: "index_daily_configuration_items_on_configuration_and_virtue"
    add_check_constraint :daily_virtue_configuration_items, "position > 0",
      name: "chk_daily_configuration_items_position_positive"

    add_reference :daily_growth_records, :daily_virtue_configuration,
      index: { name: "index_daily_growth_records_on_configuration" }

    backfill_configurations

    change_column_null :daily_growth_records, :daily_virtue_configuration_id, false
    add_foreign_key :daily_growth_records, :daily_virtue_configurations,
      column: %i[daily_virtue_configuration_id classroom_id recorded_on],
      primary_key: %i[id classroom_id recorded_on], name: "fk_growth_record_configuration_identity"
  end

  def down
    remove_foreign_key :daily_growth_records, name: "fk_growth_record_configuration_identity"
    remove_reference :daily_growth_records, :daily_virtue_configuration,
      index: { name: "index_daily_growth_records_on_configuration" }
    drop_table :daily_virtue_configuration_items
    drop_table :daily_virtue_configurations
  end

  private

  def verify_legacy_compositions!
    conflict = select_one(<<~SQL)
      WITH compositions AS (
        SELECT records.id, records.classroom_id, records.recorded_on,
          ARRAY_AGG(scores.virtue_id ORDER BY scores.virtue_id)
            FILTER (WHERE scores.id IS NOT NULL) AS virtue_ids,
          BOOL_OR(virtues.classroom_id <> records.classroom_id) AS wrong_classroom
        FROM daily_growth_records records
        LEFT JOIN daily_growth_scores scores ON scores.daily_growth_record_id = records.id
        LEFT JOIN virtues ON virtues.id = scores.virtue_id
        GROUP BY records.id, records.classroom_id, records.recorded_on
      )
      SELECT classroom_id, recorded_on
      FROM compositions
      GROUP BY classroom_id, recorded_on
      HAVING COUNT(DISTINCT virtue_ids) > 1 OR BOOL_OR(virtue_ids IS NULL) OR BOOL_OR(wrong_classroom)
      LIMIT 1
    SQL
    return unless conflict

    raise "Cannot backfill daily virtue configuration: inconsistent or invalid score composition " \
      "for classroom #{conflict.fetch('classroom_id')} on #{conflict.fetch('recorded_on')}. " \
      "Historical scores were not changed."
  end

  def backfill_configurations
    execute <<~SQL
      INSERT INTO daily_virtue_configurations (classroom_id, recorded_on, created_at, updated_at)
      SELECT DISTINCT classroom_id, recorded_on, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM daily_growth_records
    SQL

    # Legacy names cannot be reconstructed; preserve the current name without changing scores.
    execute <<~SQL
      INSERT INTO daily_virtue_configuration_items
        (daily_virtue_configuration_id, virtue_id, name, position, created_at, updated_at)
      SELECT DISTINCT configurations.id, virtues.id, virtues.name, virtues.position,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM daily_growth_records records
      JOIN daily_virtue_configurations configurations
        ON configurations.classroom_id = records.classroom_id
        AND configurations.recorded_on = records.recorded_on
      JOIN daily_growth_scores scores ON scores.daily_growth_record_id = records.id
      JOIN virtues ON virtues.id = scores.virtue_id
    SQL

    execute <<~SQL
      UPDATE daily_growth_records records
      SET daily_virtue_configuration_id = configurations.id
      FROM daily_virtue_configurations configurations
      WHERE configurations.classroom_id = records.classroom_id
        AND configurations.recorded_on = records.recorded_on
    SQL
  end
end
