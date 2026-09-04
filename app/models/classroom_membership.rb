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
  validate :teacher_memberships_are_legacy, on: :create, if: :teacher?
  validate :membership_role_must_match_user_role
  validate :classroom_must_be_active, if: :active_classroom_required?

  private

  def teacher_memberships_are_legacy
    errors.add(:role, :teacher_membership_forbidden)
  end

  def numbered_active_student_membership?
    student? && active? && student_number.present?
  end

  def active_student_membership?
    student? && active?
  end

  def active_classroom_required?
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

  def classroom_must_be_active
    return if classroom&.active?

    errors.add(:classroom, :inactive_classroom)
  end

end
