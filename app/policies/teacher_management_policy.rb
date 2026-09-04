class TeacherManagementPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.teacher if user&.admin?

      membership = user&.school_membership
      return scope.none unless user&.active_teacher? && membership&.manager? && membership.school.active?

      scope.teacher
        .joins(:school_membership)
        .where(school_memberships: { school_id: membership.school_id })
    end
  end

  def access?
    user&.admin? || school_manager?
  end

  def create?
    access?
  end

  def update_profile?
    return false unless record.teacher?
    return true if user&.admin?

    school_manager? && record.school_membership&.school_id == user.school_membership.school_id
  end

  private

  def school_manager?
    user&.active_teacher? && user.school_membership&.manager? && user.school.active?
  end
end
