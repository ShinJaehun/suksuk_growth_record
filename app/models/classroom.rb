class Classroom < ApplicationRecord
  MAX_ACTIVE_STUDENTS = 30
  has_secure_token :student_login_token

  belongs_to :school_year
  has_many :homeroom_assignments, dependent: :restrict_with_error
  has_one :current_homeroom_assignment, -> { current }, class_name: "HomeroomAssignment"
  has_one :teacher, through: :current_homeroom_assignment

  # Student memberships protect a classroom from deletion.
  has_many :classroom_memberships, dependent: :destroy
  has_many :users, through: :classroom_memberships
  before_destroy :prevent_destroy_with_students, prepend: true
  before_destroy :prevent_destroy_with_homeroom_history, prepend: true

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  before_validation :normalize_class_label, if: :class_label_changed?

  def inactive?
    !active?
  end

  def students
    users.merge(ClassroomMembership.where(role: 'student', status: 'active'))
  end

  def active_student_memberships_count
    classroom_memberships.student.active.count
  end

  validates :class_label, presence: true, length: { maximum: 50 }
  validates :class_label, format: { without: /반\z/ }, allow_blank: true
  validates :class_label, uniqueness: { scope: %i[school_year_id grade] }
  validates :grade, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    less_than_or_equal_to: 6
  }
  validate :school_year_must_not_change, on: :update
  validate :grade_must_match_current_teacher, on: :update

  private

  def normalize_class_label
    normalized = class_label.to_s.strip
    normalized = normalized.delete_suffix("반").strip
    self.class_label = normalized.presence
  end

  def school_year_must_not_change
    return unless will_save_change_to_school_year_id?

    errors.add(:school_year, :immutable)
  end

  def grade_must_match_current_teacher
    return unless will_save_change_to_grade? && teacher && teacher.grade != grade

    errors.add(:teacher, :grade_mismatch)
  end

  def prevent_destroy_with_students
    return unless classroom_memberships.student.exists?

    errors.add(:base, :students_present)
    throw :abort
  end

  def prevent_destroy_with_homeroom_history
    return unless homeroom_assignments.exists?

    errors.add(:base, :homeroom_history_present)
    throw :abort
  end

end
