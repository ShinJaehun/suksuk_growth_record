class DailyGrowthScore < ApplicationRecord
  belongs_to :daily_growth_record, inverse_of: :daily_growth_scores
  belongs_to :virtue

  validates :score, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    less_than_or_equal_to: 5
  }
  validates :virtue_id, uniqueness: { scope: :daily_growth_record_id }
  validate :virtue_matches_record_classroom
  validate :identity_must_not_change, on: :update

  private

  def virtue_matches_record_classroom
    return unless virtue && daily_growth_record&.classroom
    return if virtue.classroom_id == daily_growth_record.classroom_id

    errors.add(:virtue, :classroom_mismatch)
  end

  def identity_must_not_change
    errors.add(:daily_growth_record, :immutable) if will_save_change_to_daily_growth_record_id?
    errors.add(:virtue, :immutable) if will_save_change_to_virtue_id?
  end
end
