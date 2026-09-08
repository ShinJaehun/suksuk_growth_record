class DailyGrowthRecord < ApplicationRecord
  belongs_to :student
  belongs_to :classroom
  belongs_to :daily_virtue_configuration
  has_many :daily_growth_scores, dependent: :destroy, inverse_of: :daily_growth_record

  validates :recorded_on, presence: true, uniqueness: { scope: :student_id }
  validate :classroom_matches_student, on: :create
  validate :must_have_scores
  validate :configuration_matches_record
  validate :scores_match_configuration
  validate :identity_must_not_change, on: :update

  def average_score
    return if daily_growth_scores.empty?

    daily_growth_scores.sum(&:score).fdiv(daily_growth_scores.size)
  end

  private

  def classroom_matches_student
    return unless student && classroom && student.classroom_id != classroom_id

    errors.add(:classroom, :student_mismatch)
  end

  def must_have_scores
    errors.add(:daily_growth_scores, :blank) if daily_growth_scores.empty?
  end

  def configuration_matches_record
    return unless daily_virtue_configuration
    return if daily_virtue_configuration.classroom == classroom &&
      daily_virtue_configuration.recorded_on == recorded_on

    errors.add(:daily_virtue_configuration, :mismatch)
  end

  def scores_match_configuration
    return unless daily_virtue_configuration

    expected_ids = daily_virtue_configuration.items.map(&:virtue_id).sort
    errors.add(:daily_growth_scores, :incomplete) unless daily_growth_scores.map(&:virtue_id).sort == expected_ids
  end

  def identity_must_not_change
    errors.add(:student, :immutable) if will_save_change_to_student_id?
    errors.add(:classroom, :immutable) if will_save_change_to_classroom_id?
    errors.add(:recorded_on, :immutable) if will_save_change_to_recorded_on?
    errors.add(:daily_virtue_configuration, :immutable) if will_save_change_to_daily_virtue_configuration_id?
  end
end
