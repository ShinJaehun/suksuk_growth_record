require "rails_helper"

RSpec.describe DailyVirtueConfiguration, type: :model do
  it "captures the current names and positions as configuration items" do
    classroom = create(:classroom)
    classroom.virtues.first.update!(name: "책 읽기")

    configuration = create(:daily_virtue_configuration, :with_items, classroom:)

    expect(configuration.items.pluck(:virtue_id, :name, :position))
      .to eq(classroom.virtues.in_display_order.pluck(:id, :name, :position))
  end

  it "allows only one configuration per classroom and date" do
    configuration = create(:daily_virtue_configuration, :with_items)
    duplicate = build(:daily_virtue_configuration, :with_items,
      classroom: configuration.classroom, recorded_on: configuration.recorded_on)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:recorded_on]).to be_present
    expect do
      described_class.transaction(requires_new: true) { duplicate.save!(validate: false) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "preserves a previous date's names and score relations after a teacher rename" do
    record = create(:daily_growth_record, :with_score, recorded_on: Date.new(2026, 9, 8))
    configuration = record.daily_virtue_configuration
    item = configuration.items.first
    score = record.daily_growth_scores.first
    original_score = score.attributes
    item.virtue.update!(name: "책 읽기")

    expect(item.reload.name).to eq("독서")
    expect(score.reload.attributes).to eq(original_score)
    expect(item.virtue.reload.name).to eq("책 읽기")
  end

  it "rejects changes to an item's historical name, position, or references" do
    configuration = create(:daily_virtue_configuration, :with_items)
    item = configuration.items.first
    original = item.attributes
    other_configuration = create(:daily_virtue_configuration, :with_items)
    changes = {
      name: "다른 이름", position: 99,
      virtue_id: configuration.items.last.virtue_id,
      daily_virtue_configuration_id: other_configuration.id
    }

    changes.each do |attribute, value|
      expect(item.update(attribute => value)).to eq(false)
      expect(item.errors.added?(attribute, :immutable)).to eq(true)
      expect(item.reload.attributes).to eq(original)
    end
  end

  it "rejects a foreign classroom virtue and duplicate item" do
    configuration = create(:daily_virtue_configuration, :with_items)
    foreign_virtue = create(:classroom).virtues.first
    foreign_item = configuration.items.build(virtue: foreign_virtue, name: foreign_virtue.name, position: 4)
    expect(foreign_item).not_to be_valid
    expect(foreign_item.errors.added?(:virtue, :classroom_mismatch)).to eq(true)

    duplicate = configuration.items.first.dup
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:virtue_id]).to be_present
  end

  it "does not add or remove items after the first record" do
    record = create(:daily_growth_record, :with_score)
    configuration = record.daily_virtue_configuration
    other_virtue = record.classroom.virtues.last
    extra = configuration.items.build(virtue: other_virtue, name: other_virtue.name, position: 3)

    expect(extra.save).to eq(false)
    expect(extra.errors.added?(:base, :immutable)).to eq(true)
    expect(configuration.items.first.destroy).to eq(false)
    expect(configuration.reload.items.size).to eq(1)
  end

  it "does not change the configuration's classroom or date" do
    configuration = create(:daily_virtue_configuration, :with_items)

    expect(configuration.update(recorded_on: configuration.recorded_on + 1)).to eq(false)
    expect(configuration.errors.added?(:recorded_on, :immutable)).to eq(true)
    configuration.reload
    expect(configuration.update(classroom: create(:classroom))).to eq(false)
    expect(configuration.errors.added?(:classroom, :immutable)).to eq(true)
  end
end
