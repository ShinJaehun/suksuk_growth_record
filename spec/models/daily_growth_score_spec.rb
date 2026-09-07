require "rails_helper"

RSpec.describe DailyGrowthScore, type: :model do
  it "accepts scores from one through five" do
    record = build(:daily_growth_record)

    expect((1..5).map { |score| build(:daily_growth_score, daily_growth_record: record, score:).valid? })
      .to all(eq(true))
  end

  it "rejects scores outside one through five" do
    record = build(:daily_growth_record)

    expect([0, 6].map { |score| build(:daily_growth_score, daily_growth_record: record, score:).valid? })
      .to all(eq(false))
  end

  it "allows each virtue only once per record" do
    record = create(:daily_growth_record, :with_score)
    existing_score = record.daily_growth_scores.first

    duplicate = build(:daily_growth_score, daily_growth_record: record, virtue: existing_score.virtue)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:virtue_id]).to be_present
  end

  it "rejects a virtue from another classroom" do
    record = build(:daily_growth_record)
    outside_virtue = create(:classroom).virtues.first

    score = build(:daily_growth_score, daily_growth_record: record, virtue: outside_virtue)

    expect(score).not_to be_valid
    expect(score.errors.added?(:virtue, :classroom_mismatch)).to eq(true)
  end

  it "does not allow its record to change after creation" do
    score = create(:daily_growth_record, :with_score).daily_growth_scores.first
    other_record = build(:daily_growth_record, :with_score)

    expect(score.update(daily_growth_record: other_record)).to eq(false)
    expect(score.errors.added?(:daily_growth_record, :immutable)).to eq(true)
  end

  it "does not allow its virtue to change after creation" do
    score = create(:daily_growth_record, :with_score).daily_growth_scores.first
    other_virtue = score.daily_growth_record.classroom.virtues.second

    expect(score.update(virtue: other_virtue)).to eq(false)
    expect(score.errors.added?(:virtue, :immutable)).to eq(true)
  end

  it "allows its score value to change" do
    score = create(:daily_growth_record, :with_score).daily_growth_scores.first

    expect(score.update(score: 5)).to eq(true)
    expect(score.reload.score).to eq(5)
  end

  it "builds against an unpersisted record without writing factory associations" do
    record = build(:daily_growth_record)
    classroom_count = Classroom.count
    virtue_count = Virtue.count

    score = build(:daily_growth_score, daily_growth_record: record)

    expect(score.virtue).to be_present
    expect(Classroom.count).to eq(classroom_count)
    expect(Virtue.count).to eq(virtue_count)
  end
end
