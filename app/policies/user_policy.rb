class UserPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      user.admin? ? scope.all : scope.where(id: user.id)
    end
  end

  def index?
    user.admin?
  end

  def create?
    user.admin?
  end

  def show?
    return true if user&.admin?

    if user&.active_teacher?
      return true if user == record

      # 담임인 반 학생들 정보만 조회 가능
      classroom = user.assigned_classroom
      return classroom&.active? && classroom.school.active? &&
        ClassroomMembership.exists?(user_id: record.id, classroom_id: classroom.id, role: "student")
    end
    # 학생은 본인만
    user&.student? && user.id == record.id
  end

  # Admin 영역에서 교사 계정 수정 권한
  def edit?
    update?
  end

  def update?
    user&.admin? && record.teacher?
  end

  def manage_own_student_pin?
    user&.student? && record.student? && user.id == record.id
  end

  def destroy_student?
    return false unless record.student?
    return true if user&.admin?
    return false unless user&.active_teacher?

    classroom = user.assigned_classroom
    classroom&.active? && classroom.school.active? &&
      ClassroomMembership.exists?(user_id: record.id, classroom_id: classroom.id, role: "student")
  end

  def manage_student_account?
    destroy_student?
  end

  def manage_student_password?
    destroy_student?
  end

  def deactivate_teacher?
    teacher_status_change_allowed? && record.active?
  end

  def reactivate_teacher?
    teacher_status_change_allowed? && record.inactive?
  end

  private

  def teacher_status_change_allowed?
    return false unless record.teacher?
    return true if user&.admin?
    return false unless user&.active_teacher?
    return false if user.id == record.id

    manager_membership = user.school_membership
    target_membership = record.school_membership

    return false unless manager_membership&.manager?
    return false unless target_membership&.member?

    manager_membership.school_id == target_membership.school_id
  end
end
