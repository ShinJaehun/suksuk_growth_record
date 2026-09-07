require "rails_helper"

RSpec.describe DailyGrowthRecords::Save do
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
  end

  it "rolls back the record and scores when any active virtue score is missing" do
    student = create(:student)
    virtues = student.classroom.virtues.active.to_a

    expect do
      described_class.call(student:, scores: scores_for(virtues.first(2)), reflection: nil)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(DailyGrowthRecord.count).to eq(0)
    expect(DailyGrowthScore.count).to eq(0)
  end

  it "updates only the virtue composition captured by the existing record" do
    student = create(:student)
    original_virtues = student.classroom.virtues.active.to_a
    record = described_class.call(student:, scores: scores_for(original_virtues), reflection: nil)
    added_virtue = create(:virtue, classroom: student.classroom, position: 4)

    described_class.call(student:, record:, scores: scores_for(original_virtues, 4), reflection: "수정")

    expect(record.reload.daily_growth_scores.map(&:virtue)).to match_array(original_virtues)
    expect(record.daily_growth_scores.map(&:virtue)).not_to include(added_virtue)
  end

  it "updates a captured virtue after it becomes inactive" do
    student = create(:student)
    virtues = student.classroom.virtues.active.to_a
    record = described_class.call(student:, scores: scores_for(virtues), reflection: nil)
    virtues.first.update!(active: false)

    described_class.call(student:, record:, scores: scores_for(virtues, 5), reflection: nil)

    expect(record.reload.daily_growth_scores.find_by!(virtue: virtues.first).score).to eq(5)
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
end
