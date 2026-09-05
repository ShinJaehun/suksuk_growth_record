class Classroom < ApplicationRecord
  MAX_ACTIVE_STUDENTS = 30
  has_secure_token :student_login_token

  belongs_to :school
  belongs_to :teacher, class_name: 'User', optional: true, inverse_of: :assigned_classroom

  # Student memberships protect a classroom from deletion.
  has_many :classroom_memberships, dependent: :destroy
  has_many :users, through: :classroom_memberships
  before_destroy :prevent_destroy_with_students, prepend: true

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def inactive?
    !active?
  end

  def students
    users.merge(ClassroomMembership.where(role: 'student', status: 'active'))
  end

  def active_student_memberships_count
    classroom_memberships.student.active.count
  end

  validates :name, length: { maximum: 50 }
  validates :grade, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    less_than_or_equal_to: 6
  }
  validate :school_must_not_change, on: :update
  validates :teacher_id, uniqueness: true, allow_nil: true
  validate :teacher_assignment_must_be_valid
  validate :teacher_assignment_must_not_replace_existing_teacher

  private

  def school_must_not_change
    return unless will_save_change_to_school_id?

    errors.add(:school, :immutable)
  end

  def prevent_destroy_with_students
    return unless classroom_memberships.student.exists?

    errors.add(:base, :students_present)
    throw :abort
  end

  def teacher_assignment_must_be_valid
    return unless teacher

    errors.add(:teacher, :invalid) unless teacher.teacher?
    errors.add(:teacher, :inactive) unless teacher.active?
    errors.add(:teacher, :inactive_classroom) if !active? && will_save_change_to_teacher_id?

    errors.add(:teacher, :school_membership_required) unless teacher.school_year
    return unless teacher.school_year

    errors.add(:teacher, :school_mismatch) unless teacher.annual_school&.id == school_id
    errors.add(:teacher, :grade_required) if teacher.grade.nil?
    errors.add(:teacher, :grade_mismatch) unless teacher.grade == grade
  end

  def teacher_assignment_must_not_replace_existing_teacher
    return unless will_save_change_to_teacher_id?
    return if teacher_id_in_database.blank?
    return if teacher_id.blank?
    return if teacher_id == teacher_id_in_database

    errors.add(:teacher, :already_assigned)
  end
end
