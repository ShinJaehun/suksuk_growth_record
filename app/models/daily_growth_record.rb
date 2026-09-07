class DailyGrowthRecord < ApplicationRecord
  belongs_to :student
  belongs_to :classroom
  has_many :daily_growth_scores, dependent: :destroy, inverse_of: :daily_growth_record

  validates :recorded_on, presence: true, uniqueness: { scope: :student_id }
  validate :classroom_matches_student, on: :create
  validate :must_have_scores
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

  def identity_must_not_change
    errors.add(:student, :immutable) if will_save_change_to_student_id?
    errors.add(:classroom, :immutable) if will_save_change_to_classroom_id?
    errors.add(:recorded_on, :immutable) if will_save_change_to_recorded_on?
  end
end
