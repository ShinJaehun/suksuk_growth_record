require 'rails_helper'

RSpec.describe Virtue, type: :model do
  it 'bootstraps the three default virtues for a new classroom' do
    classroom = create(:classroom)

    expect(classroom.virtues.pluck(:name, :position)).to eq(
      [['독서', 1], ['봉사', 2], ['감사', 3]]
    )
    colors = classroom.virtues.pluck(:color_key)
    expect(colors).to all(be_in(Virtue::COLORS.keys))
    expect(colors.uniq.size).to eq(3)
  end

  it 'does not duplicate defaults when bootstrap runs again' do
    classroom = create(:classroom)
    original_colors = classroom.virtues.order(:id).pluck(:color_key)

    expect { Virtues::BootstrapDefaults.call(classroom:) }
      .not_to(change { classroom.virtues.count })
    expect(classroom.virtues.order(:id).pluck(:color_key)).to eq(original_colors)
  end

  it 'does not restore original defaults after a default virtue is renamed' do
    classroom = create(:classroom)
    classroom.virtues.find_by!(name: '독서').update!(name: '책 읽기')

    Virtues::BootstrapDefaults.call(classroom:)

    expect(classroom.virtues.pluck(:name)).to contain_exactly('책 읽기', '봉사', '감사')
  end

  it 'does not allow its classroom to change after creation' do
    virtue = create(:classroom).virtues.first

    expect(virtue.update(classroom: create(:classroom))).to eq(false)
    expect(virtue.errors.added?(:classroom, :immutable)).to eq(true)
  end

  it 'allows at most five active virtues' do
    classroom = create(:classroom)
    create(:virtue, classroom:, position: 4)
    create(:virtue, classroom:, position: 5)

    sixth = build(:virtue, classroom:, position: 6)

    expect(sixth).not_to be_valid
    expect(sixth.errors.added?(:active, :too_many)).to eq(true)
  end

  it 'prevents deactivating the last active virtue' do
    classroom = create(:classroom)
    classroom.virtues.where.not(name: '독서').update_all(active: false)
    last_virtue = classroom.virtues.find_by!(name: '독서')

    expect(last_virtue.update(active: false)).to eq(false)
    expect(last_virtue.errors.added?(:active, :last_active)).to eq(true)
  end

  it 'preserves an inactive virtue and its historical score' do
    record = create(:daily_growth_record, :with_score)
    virtue = record.daily_growth_scores.first.virtue

    expect(virtue.update(active: false)).to eq(true)
    expect(record.reload.daily_growth_scores.first.virtue).to eq(virtue)
  end

  it 'keeps the score relation when a virtue is renamed' do
    record = create(:daily_growth_record, :with_score)
    virtue = record.daily_growth_scores.first.virtue

    virtue.update!(name: '책 읽기')

    expect(record.reload.daily_growth_scores.first.virtue.name).to eq('책 읽기')
  end

  it 'accepts every palette key and rejects arbitrary colors' do
    virtue = create(:classroom).virtues.first
    virtue.update!(active: false)

    Virtue::COLORS.each do |key, hex|
      virtue.color_key = key
      expect(virtue).to be_valid
      expect(virtue.color_hex).to eq(hex)
    end

    ['unknown', '#123456', ''].each do |invalid_color|
      virtue.color_key = invalid_color
      expect(virtue).not_to be_valid
      expect(virtue.errors.added?(:color_key, :inclusion, value: invalid_color)).to eq(true)
    end
  end

  it 'automatically chooses unused active colors and keeps them after saving' do
    classroom = create(:classroom)
    used_colors = classroom.virtues.active.pluck(:color_key)

    virtue = create(:virtue, classroom:, color_key: '')

    expect(Virtue::COLORS).to have_key(virtue.color_key)
    expect(used_colors).not_to include(virtue.color_key)
    expect { virtue.update!(name: '새 이름') }.not_to(change { virtue.reload.color_key })
  end

  it 'rechecks automatic color assignment under the classroom lock' do
    classroom = create(:classroom)
    first = build(:virtue, classroom:)
    second = build(:virtue, classroom:)
    expect(first).to be_valid
    expect(second).to be_valid

    first.save!
    second.save!

    expect(first.reload.color_key).not_to eq(second.reload.color_key)
  end

  it 'retains an explicit palette choice' do
    virtue = create(:virtue, color_key: 'rose')

    expect(virtue.reload.color_key).to eq('rose')
  end

  it 'requires distinct colors for active virtues in the same Classroom but allows inactive duplicates' do
    classroom = create(:classroom)
    first, second = classroom.virtues.in_display_order.first(2)

    second.color_key = first.color_key
    expect(second).not_to be_valid
    expect(second.errors.added?(:color_key, :taken)).to eq(true)

    second.active = false
    expect(second).to be_valid
  end

  it "keeps historical scores while changing and retiring their virtue's color" do
    record = create(:daily_growth_record, :with_score)
    score = record.daily_growth_scores.first
    original_value = score.score
    score.virtue.update!(color_key: 'orange')
    score.virtue.update!(active: false)

    expect(score.reload.score).to eq(original_value)
    expect(score.virtue.reload.color_key).to eq('orange')
  end
end
