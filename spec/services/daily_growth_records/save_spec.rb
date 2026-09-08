require "rails_helper"

RSpec.describe DailyGrowthRecords::Save do
  include ActiveSupport::Testing::TimeHelpers

  def scores_for(virtues, value = 3)
    virtues.index_with { value }.transform_keys(&:id)
  end

  it "creates today's record with every currently active virtue" do
    student = create(:student)
    virtues = student.classroom.virtues.active.to_a

    record = described_class.call(student:, scores: scores_for(virtues), reflection: "오늘의 생각")

    expect(record.recorded_on).to eq(Time.zone.today)
    expect(record.classroom).to eq(student.classroom)
    expect(record.daily_growth_scores.map(&:virtue)).to match_array(virtues)
    configuration = record.daily_virtue_configuration
    expect(configuration).to have_attributes(classroom: student.classroom, recorded_on: Time.zone.today)
    expect(configuration.items.pluck(:virtue_id, :name))
      .to match_array(virtues.map { |virtue| [virtue.id, virtue.name] })
    expect(configuration.items.pluck(:position)).to eq(virtues.map(&:position))
  end

  it "rolls back the record and scores when any active virtue score is missing" do
    student = create(:student)
    virtues = student.classroom.virtues.active.to_a

    expect do
      described_class.call(student:, scores: scores_for(virtues.first(2)), reflection: nil)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(DailyGrowthRecord.count).to eq(0)
    expect(DailyGrowthScore.count).to eq(0)
    expect(DailyVirtueConfiguration.count).to eq(0)
    expect(DailyVirtueConfigurationItem.count).to eq(0)
  end

  it "updates only the virtue composition captured by the existing record" do
    student = create(:student)
    original_virtues = student.classroom.virtues.active.to_a
    record = described_class.call(student:, scores: scores_for(original_virtues), reflection: nil)
    original_scores = record.daily_growth_scores.pluck(:id, :virtue_id)
    configuration = record.daily_virtue_configuration
    original_items = configuration.items.pluck(:id, :virtue_id, :name, :position)
    original_virtues.first.update!(name: "책 읽기")
    added_virtue = create(:virtue, classroom: student.classroom, position: 4)
    original_virtues.last.update!(active: false)

    described_class.call(student:, record:, scores: scores_for(original_virtues, 4), reflection: "수정")

    expect(record.reload.daily_growth_scores.map(&:virtue)).to match_array(original_virtues)
    expect(record.daily_growth_scores.map(&:virtue)).not_to include(added_virtue)
    expect(record.daily_growth_scores.pluck(:id, :virtue_id)).to match_array(original_scores)
    expect(record.daily_virtue_configuration).to eq(configuration)
    expect(configuration.reload.items.pluck(:id, :virtue_id, :name, :position)).to eq(original_items)
    expect(record.daily_growth_scores.pluck(:score)).to all(eq(4))
    expect(record.reflection).to eq("수정")

    later_student = create(:student, classroom: student.classroom)
    later_record = described_class.call(student: later_student, scores: scores_for(original_virtues))

    expect(later_record.recorded_on).to eq(record.recorded_on)
    expect(later_record.daily_growth_scores.map(&:virtue)).to match_array(original_virtues)
    expect(later_record.daily_virtue_configuration).to eq(configuration)
    expect(later_record.daily_virtue_configuration.items.pluck(:id, :virtue_id, :name, :position)).to eq(original_items)
    expect(later_record.daily_virtue_configuration.items.find_by!(virtue: original_virtues.first).name).to eq("독서")
    expect(later_record.daily_growth_scores.find_by(virtue: added_virtue)).to be_nil
  end

  it "updates a captured virtue after it becomes inactive" do
    student = create(:student)
    virtues = student.classroom.virtues.active.to_a
    record = described_class.call(student:, scores: scores_for(virtues), reflection: nil)
    original_scores = record.daily_growth_scores.pluck(:id, :virtue_id)
    virtues.first.update!(active: false)

    described_class.call(student:, record:, scores: scores_for(virtues, 5), reflection: nil)

    expect(record.reload.daily_growth_scores.find_by!(virtue: virtues.first).score).to eq(5)
    expect(record.daily_growth_scores.pluck(:id, :virtue_id)).to match_array(original_scores)

    later_student = create(:student, classroom: student.classroom)
    later_record = described_class.call(student: later_student, scores: scores_for(virtues))

    expect(later_record.daily_growth_scores.map(&:virtue)).to match_array(virtues)
    expect(later_record.daily_growth_scores.map(&:virtue)).to include(virtues.first)
    expect(later_record.daily_virtue_configuration).to eq(record.daily_virtue_configuration)
  end

  it "rejects a student-side update to a past record" do
    student = create(:student)
    record = build(:daily_growth_record, :with_score, student:, recorded_on: Time.zone.yesterday)
    record.save!
    scores = record.daily_growth_scores.index_with { 4 }.transform_keys(&:virtue_id)

    expect do
      described_class.call(student:, record:, scores:, reflection: nil)
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "allows a blank reflection" do
    student = create(:student)
    virtues = student.classroom.virtues.active.to_a

    record = described_class.call(student:, scores: scores_for(virtues), reflection: nil)

    expect(record.reflection).to be_nil
  end

  it "captures teacher changes made before the first record" do
    student = create(:student)
    virtues = student.classroom.virtues.active.to_a
    virtues.first.update!(name: "책 읽기")
    virtues.last.update!(active: false)
    added_virtue = create(:virtue, classroom: student.classroom)
    active_virtues = student.classroom.virtues.active.in_display_order.to_a

    record = described_class.call(student:, scores: scores_for(active_virtues))

    expect(record.daily_virtue_configuration.items.pluck(:virtue_id, :name))
      .to match_array(active_virtues.map { |virtue| [virtue.id, virtue.name] })
    expect(record.daily_growth_scores.map(&:virtue)).to include(added_virtue)
    expect(record.daily_growth_scores.map(&:virtue)).not_to include(virtues.last)
  end

  it "applies later teacher changes to the next date without changing the past configuration" do
    travel_to(Time.zone.local(2026, 9, 8, 8, 30)) do
      student = create(:student)
      virtues = student.classroom.virtues.active.to_a
      today_record = described_class.call(student:, scores: scores_for(virtues))
      old_items = today_record.daily_virtue_configuration.items.pluck(:virtue_id, :name, :position)
      virtues.first.update!(name: "책 읽기")
      virtues.last.update!(active: false)
      create(:virtue, classroom: student.classroom)
      travel_to(Time.zone.local(2026, 9, 9, 9))
      current_virtues = student.classroom.virtues.active.to_a

      next_record = described_class.call(student:, scores: scores_for(current_virtues))

      expect(next_record.daily_virtue_configuration).not_to eq(today_record.daily_virtue_configuration)
      expect(next_record.daily_virtue_configuration.items.pluck(:virtue_id, :name))
        .to match_array(current_virtues.map { |virtue| [virtue.id, virtue.name] })
      expect(today_record.daily_virtue_configuration.reload.items.pluck(:virtue_id, :name, :position)).to eq(old_items)
    end
  end
end
