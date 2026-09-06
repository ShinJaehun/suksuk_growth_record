class ClassroomPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      active_scope = scope.joins(school_year: :school)
        .merge(SchoolYear.active)
        .merge(School.active)
      return active_scope if admin?

      if teacher? && user.school_manager?
        return active_scope.where(school_year_id: user.school_year_id)
      end

      # Teachers can see only their classrooms
      if teacher?
        return active_scope.joins(:current_homeroom_assignment)
          .where(homeroom_assignments: { teacher_id: user.id }, active: true)
      end

      # Students can see only their classrooms
      if user.is_a?(Student)
        return scope.none unless user.active?

        return active_scope.where(id: user.classroom_id, active: true)
      end

      if student?
        return active_scope.joins(:classroom_memberships)
                    .where(classroom_memberships: { user_id: user.id, role: 'student', status: 'active' })
                    .distinct
      end

      scope.none
    end
  end

  def index?
    admin? || teacher? || student?
  end

  def show?
    return true if admin?
    return false unless active_school?

    school_manager_of?(record) || member_of?(record)
  end

  def create?
    admin? || (school_manager? && user.annual_school&.active?)
  end

  def new?
    create?
  end

  def update?
    manage_structure?
  end

  def edit?
    active_school? && !!(admin? || school_manager_of?(record))
  end

  def destroy?
    active_school? && !!admin?
  end

  def manage_members?
    active_school? && active_classroom? && (admin? || teacher_of?(record))
  end

  def manage_structure?
    active_school? && active_classroom? && !!(admin? || school_manager_of?(record))
  end

  def manage_operations?
    active_school? && active_classroom? && !!(admin? || teacher_of?(record))
  end

  def deactivate?
    active_school? && active_classroom? && !!(admin? || school_manager_of?(record))
  end

  def reactivate?
    active_school? && inactive_classroom? && !!(admin? || school_manager_of?(record))
  end

  def view_student_data?
    return false unless active_school?
    return true if admin?
    return teacher_of?(record) if teacher?
    return student_of?(record) if student?

    false
  end

  private

  def active_school?
    # The shared new-classroom form checks structure permission before an admin selects a school.
    return true if admin? && record.respond_to?(:new_record?) && record.new_record?

    record.respond_to?(:school_year) && record.school_year&.active? &&
      record.school_year.school.active?
  end

  def active_classroom?
    record.respond_to?(:active?) && record.active?
  end

  def inactive_classroom?
    record.respond_to?(:active?) && !record.active?
  end

  def school_manager?
    teacher? && user.school_manager?
  end

  def school_manager_of?(classroom)
    school_manager? && classroom.school_year_id == user.school_year_id
  end

  def teacher_of?(classroom)
    return false unless user&.active_teacher?

    classroom.teacher == user
  end

  def member_of?(classroom)
    return false unless user

    return teacher_of?(classroom) if teacher?
    return student_of?(classroom) if student?

    false
  end

  def student_of?(classroom)
    if user.is_a?(Student)
      return user.active? && classroom.id == user.classroom_id && classroom.active? &&
        classroom.school_year.active? && classroom.school_year.school.active?
    end

    return false unless user.is_a?(User) && user.student?

    classroom.classroom_memberships.exists?(user_id: user.id, role: 'student', status: 'active')
  end
end
