class ClassroomMembership < ApplicationRecord
  belongs_to :user
  belongs_to :classroom

  enum :role, { student: "student", teacher: "teacher" }
  enum :status, { active: "active", inactive: "inactive" }

  scope :in_roster_order, -> {
    joins(:user).order(
      Arel.sql("classroom_memberships.student_number ASC NULLS LAST"),
      Arel.sql("users.name ASC"),
      Arel.sql("classroom_memberships.user_id ASC"),
      Arel.sql("classroom_memberships.id ASC")
    )
  }

  validates :student_number,
    numericality: { only_integer: true, greater_than_or_equal_to: 1 },
    allow_nil: true
  validates :student_number,
    uniqueness: {
      scope: :classroom_id,
      conditions: -> { student.active.where.not(student_number: nil) }
    },
    if: :numbered_active_student_membership?
  validate :one_active_classroom_per_student, if: :active_student_membership?
  validate :membership_role_must_match_user_role
  validate :teacher_must_belong_to_classroom_school, if: :teacher?
  validate :teacher_must_be_active, if: :teacher_assignment_changed?
  validate :classroom_must_be_active, if: :active_classroom_required?
  validate :teacher_must_not_have_student_number, if: :teacher?
  validate :teacher_membership_must_be_active

  private

  def numbered_active_student_membership?
    student? && active? && student_number.present?
  end

  def active_student_membership?
    student? && active?
  end

  def teacher_assignment_changed?
    teacher? && assignment_relationship_changed?
  end

  def active_classroom_required?
    return teacher_assignment_changed? if teacher?

    student? && (
      assignment_relationship_changed? ||
      will_save_change_to_status?(to: "active")
    )
  end

  def assignment_relationship_changed?
    new_record? ||
      will_save_change_to_user_id? ||
      will_save_change_to_classroom_id? ||
      will_save_change_to_role?
  end

  def one_active_classroom_per_student
    return if user_id.blank?

    existing_memberships = self.class.student.active.where(user_id: user_id)
    existing_memberships = existing_memberships.where.not(id: id) if persisted?
    return unless existing_memberships.exists?

    errors.add(:base, :active_student_membership_taken)
  end

  def membership_role_must_match_user_role
    return if user.blank?
    return if teacher? && user.teacher?
    return if student? && user.student?

    errors.add(:base, :role_mismatch)
  end

  def teacher_must_belong_to_classroom_school
    return if user.blank? || classroom.blank?

    school_membership = user.school_membership
    if school_membership.blank?
      errors.add(:base, :teacher_school_required)
    elsif school_membership.school_id != classroom.school_id
      errors.add(:base, :teacher_school_mismatch)
    end
  end

  def teacher_must_be_active
    return if user&.active?

    errors.add(:user, :inactive_teacher)
  end

  def classroom_must_be_active
    return if classroom&.active?

    errors.add(:classroom, :inactive_classroom)
  end

  def teacher_must_not_have_student_number
    return if student_number.blank?

    errors.add(:student_number, :teacher_student_number_forbidden)
  end

  def teacher_membership_must_be_active
    return unless teacher? && inactive?

    errors.add(:status, :teacher_must_be_active)
  end
end
