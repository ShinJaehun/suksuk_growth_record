class Classroom < ApplicationRecord
    MAX_ACTIVE_STUDENTS = 30
    has_secure_token :student_login_token

    belongs_to :school

    # Empty classrooms may remove their remaining teacher memberships on deletion.
    # Student memberships protect a classroom from deletion.
    has_many :classroom_memberships, dependent: :destroy
    has_many :users, through: :classroom_memberships
    before_destroy :prevent_destroy_with_students, prepend: true

    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }

    def students
      users.merge(ClassroomMembership.where(role: "student", status: "active"))
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
end
