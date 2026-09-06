class HomeroomAssignment < ApplicationRecord
  belongs_to :classroom, inverse_of: :homeroom_assignments
  belongs_to :teacher, class_name: 'User', inverse_of: :homeroom_assignments

  scope :current, -> { where(ended_on: nil) }

  validates :started_on, presence: true
  validates :classroom_id, uniqueness: { conditions: -> { current } }, if: :current?
  validates :teacher_id, uniqueness: { conditions: -> { current } }, if: :current?
  validate :ended_on_cannot_precede_started_on
  validate :assignment_participants_are_compatible, on: :create
  validate :current_assignment_lifecycle, on: :create, if: :current?
  validate :school_year_allows_update, on: :update
  validate :participants_must_not_change, on: :update
  validate :ended_history_must_not_change, on: :update

  def current?
    ended_on.nil?
  end

  private

  def ended_on_cannot_precede_started_on
    return if ended_on.nil? || started_on.nil? || ended_on >= started_on

    errors.add(:ended_on, :invalid)
  end

  def assignment_participants_are_compatible
    return unless classroom && teacher

    errors.add(:teacher, :invalid) unless teacher.teacher?
    errors.add(:teacher, :school_mismatch) unless teacher.school_year_id == classroom.school_year_id
    errors.add(:teacher, :grade_required) if teacher.grade.nil?
    errors.add(:teacher, :grade_mismatch) unless teacher.grade == classroom.grade
  end

  def current_assignment_lifecycle
    return unless classroom && teacher

    errors.add(:teacher, :inactive) unless teacher.active?
    errors.add(:classroom, :inactive) unless classroom.active?
    errors.add(:classroom, :inactive_school_year) if classroom.school_year.archived?
    errors.add(:classroom, :inactive_school) unless classroom.school_year.school.active?
  end

  def school_year_allows_update
    return unless classroom&.school_year&.archived?

    errors.add(:base, :archived_school_year)
  end

  def participants_must_not_change
    errors.add(:classroom, :immutable) if will_save_change_to_classroom_id?
    errors.add(:teacher, :immutable) if will_save_change_to_teacher_id?
    errors.add(:started_on, :immutable) if will_save_change_to_started_on?
  end

  def ended_history_must_not_change
    return if ended_on_in_database.nil?
    return unless has_changes_to_save?

    errors.add(:base, :historical_assignment_immutable)
  end
end
