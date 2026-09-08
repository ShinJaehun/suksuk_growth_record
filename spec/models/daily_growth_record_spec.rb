require "rails_helper"

RSpec.describe DailyGrowthRecord, type: :model do
  def build_record(student:, recorded_on:, score: 3, reflection: nil)
    record = build(:daily_growth_record, :with_score, student:, recorded_on:, reflection:)
    record.daily_growth_scores.first.score = score
    record
  end

  it "allows only one record per student and date" do
    student = create(:student)
    build_record(student:, recorded_on: Time.zone.today).save!

    duplicate = build_record(student:, recorded_on: Time.zone.today)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:recorded_on]).to be_present
  end

  it "preserves its classroom attribution independently of the student's current classroom" do
    student = create(:student)
    record = build_record(student:, recorded_on: Time.zone.today)
    record.save!
    original_classroom = record.classroom

    student.update_column(:classroom_id, create(:classroom).id)

    expect(record.reload.classroom).to eq(original_classroom)
  end

  it "rejects a classroom other than the student's classroom at creation" do
    student = create(:student)
    record = described_class.new(
      student:,
      classroom: create(:classroom),
      recorded_on: Time.zone.today
    )
    record.daily_growth_scores.build(virtue: record.classroom.virtues.first, score: 3)

    expect(record).not_to be_valid
    expect(record.errors.added?(:classroom, :student_mismatch)).to eq(true)
  end

  it "allows a blank reflection" do
    record = build_record(student: create(:student), recorded_on: Time.zone.today, reflection: nil)

    expect(record).to be_valid
  end

  it "averages only the scores that exist on the record" do
    student = create(:student)
    record = described_class.new(student:, classroom: student.classroom, recorded_on: Time.zone.today)
    virtues = student.classroom.virtues.active.first(2)
    record.daily_growth_scores.build(virtue: virtues.first, score: 3)
    record.daily_growth_scores.build(virtue: virtues.second, score: 4)

    expect(record.average_score).to eq(3.5)
  end

  it "does not allow its student to change after creation" do
    record = build_record(student: create(:student), recorded_on: Time.zone.today)
    record.save!

    expect(record.update(student: create(:student))).to eq(false)
    expect(record.errors.added?(:student, :immutable)).to eq(true)
  end

  it "does not allow its classroom to change after creation" do
    record = build_record(student: create(:student), recorded_on: Time.zone.today)
    record.save!

    expect(record.update(classroom: create(:classroom))).to eq(false)
    expect(record.errors.added?(:classroom, :immutable)).to eq(true)
  end

  it "does not allow its recorded date to change after creation" do
    record = build_record(student: create(:student), recorded_on: Time.zone.today)
    record.save!

    expect(record.update(recorded_on: Time.zone.yesterday)).to eq(false)
    expect(record.errors.added?(:recorded_on, :immutable)).to eq(true)
  end

  it "allows its reflection to change" do
    record = build_record(student: create(:student), recorded_on: Time.zone.today)
    record.save!

    expect(record.update(reflection: "수정한 생각")).to eq(true)
    expect(record.reload.reflection).to eq("수정한 생각")
  end

  it "builds without persisting factory associations" do
    classroom_count = Classroom.count
    virtue_count = Virtue.count

    record = build(:daily_growth_record)

    expect(record).to be_new_record
    expect(Classroom.count).to eq(classroom_count)
    expect(Virtue.count).to eq(virtue_count)
  end

  it "requires a configuration for a new record" do
    record = build(:daily_growth_record, :with_score)
    record.daily_virtue_configuration = nil

    expect(record).not_to be_valid
    expect(record.errors[:daily_virtue_configuration]).to be_present
  end

  it "rejects configurations from another classroom or date" do
    record = build(:daily_growth_record, :with_score, student: create(:student))
    foreign = create(:daily_virtue_configuration, :with_items)
    other_date = create(:daily_virtue_configuration, :with_items,
      classroom: record.classroom, recorded_on: record.recorded_on - 1)

    [foreign, other_date].each do |configuration|
      record.daily_virtue_configuration = configuration
      expect(record).not_to be_valid
      expect(record.errors.added?(:daily_virtue_configuration, :mismatch)).to eq(true)
    end
  end

  it "cannot switch an existing record's configuration" do
    record = create(:daily_growth_record, :with_score)
    other_date = create(:daily_virtue_configuration, :with_items,
      classroom: record.classroom, recorded_on: record.recorded_on - 1)

    expect(record.update(daily_virtue_configuration: other_date)).to eq(false)
    expect(record.errors.added?(:daily_virtue_configuration, :immutable)).to eq(true)
  end

  it "requires exactly the configuration's score composition" do
    record = build(:daily_growth_record, :with_score, student: create(:student))
    record.daily_growth_scores.build(virtue: record.classroom.virtues.last, score: 3)

    expect(record).not_to be_valid
    expect(record.errors.added?(:daily_growth_scores, :incomplete)).to eq(true)
  end

  it "enforces the configuration's classroom and date in the database" do
    record = create(:daily_growth_record, :with_score)
    foreign = create(:daily_virtue_configuration, :with_items)

    expect do
      described_class.transaction(requires_new: true) do
        record.update_columns(daily_virtue_configuration_id: foreign.id)
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
