require "rails_helper"

RSpec.describe Virtue, type: :model do
  it "bootstraps the three default virtues for a new classroom" do
    classroom = create(:classroom)

    expect(classroom.virtues.pluck(:name, :position)).to eq(
      [["독서", 1], ["봉사", 2], ["감사", 3]]
    )
  end

  it "does not duplicate defaults when bootstrap runs again" do
    classroom = create(:classroom)

    expect { Virtues::BootstrapDefaults.call(classroom:) }
      .not_to change { classroom.virtues.count }
  end

  it "does not restore original defaults after a default virtue is renamed" do
    classroom = create(:classroom)
    classroom.virtues.find_by!(name: "독서").update!(name: "책 읽기")

    Virtues::BootstrapDefaults.call(classroom:)

    expect(classroom.virtues.pluck(:name)).to contain_exactly("책 읽기", "봉사", "감사")
  end

  it "does not allow its classroom to change after creation" do
    virtue = create(:classroom).virtues.first

    expect(virtue.update(classroom: create(:classroom))).to eq(false)
    expect(virtue.errors.added?(:classroom, :immutable)).to eq(true)
  end

  it "allows at most five active virtues" do
    classroom = create(:classroom)
    create(:virtue, classroom:, position: 4)
    create(:virtue, classroom:, position: 5)

    sixth = build(:virtue, classroom:, position: 6)

    expect(sixth).not_to be_valid
    expect(sixth.errors.added?(:active, :too_many)).to eq(true)
  end

  it "prevents deactivating the last active virtue" do
    classroom = create(:classroom)
    classroom.virtues.where.not(name: "독서").update_all(active: false)
    last_virtue = classroom.virtues.find_by!(name: "독서")

    expect(last_virtue.update(active: false)).to eq(false)
    expect(last_virtue.errors.added?(:active, :last_active)).to eq(true)
  end

  it "preserves an inactive virtue and its historical score" do
    record = create(:daily_growth_record, :with_score)
    virtue = record.daily_growth_scores.first.virtue

    expect(virtue.update(active: false)).to eq(true)
    expect(record.reload.daily_growth_scores.first.virtue).to eq(virtue)
  end

  it "keeps the score relation when a virtue is renamed" do
    record = create(:daily_growth_record, :with_score)
    virtue = record.daily_growth_scores.first.virtue

    virtue.update!(name: "책 읽기")

    expect(record.reload.daily_growth_scores.first.virtue.name).to eq("책 읽기")
  end
end
