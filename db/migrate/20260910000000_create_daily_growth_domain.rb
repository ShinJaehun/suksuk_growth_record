class CreateDailyGrowthDomain < ActiveRecord::Migration[8.1]
  DEFAULT_VIRTUES = [
    ["독서", 1],
    ["봉사", 2],
    ["감사", 3]
  ].freeze

  def up
    create_table :virtues do |t|
      t.references :classroom, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false
      t.timestamps
    end

    add_check_constraint :virtues, "position > 0", name: "chk_virtues_position_positive"

    create_table :daily_growth_records do |t|
      t.references :student, null: false, foreign_key: true
      t.references :classroom, null: false, foreign_key: true
      t.date :recorded_on, null: false
      t.text :reflection
      t.timestamps
    end

    add_index :daily_growth_records,
              %i[student_id recorded_on],
              unique: true,
              name: "index_daily_growth_records_on_student_and_date"

    create_table :daily_growth_scores do |t|
      t.references :daily_growth_record, null: false, foreign_key: true
      t.references :virtue, null: false, foreign_key: true
      t.integer :score, null: false
      t.timestamps
    end

    add_index :daily_growth_scores,
              %i[daily_growth_record_id virtue_id],
              unique: true,
              name: "index_daily_growth_scores_on_record_and_virtue"
    add_check_constraint :daily_growth_scores,
                         "score BETWEEN 1 AND 5",
                         name: "chk_daily_growth_scores_range"

    bootstrap_current_classrooms
  end

  def down
    drop_table :daily_growth_scores
    drop_table :daily_growth_records
    drop_table :virtues
  end

  private

  def bootstrap_current_classrooms
    DEFAULT_VIRTUES.each do |name, position|
      quoted_name = connection.quote(name)

      execute <<~SQL.squish
        INSERT INTO virtues (classroom_id, name, active, position, created_at, updated_at)
        SELECT classrooms.id, #{quoted_name}, TRUE, #{position}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM classrooms
        INNER JOIN school_years ON school_years.id = classrooms.school_year_id
        WHERE school_years.status = 'active'
          AND NOT EXISTS (
            SELECT 1
            FROM virtues
            WHERE virtues.classroom_id = classrooms.id
              AND virtues.name = #{quoted_name}
          )
      SQL
    end
  end
end
