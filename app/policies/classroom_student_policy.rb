class ClassroomStudentPolicy < ApplicationPolicy
  def create?
    classroom = record.classroom
    return false unless classroom&.active? && classroom.school_year&.active? &&
      classroom.school_year.school.active?
    return true if admin?
    teacher_of?(record.classroom)
  end

  def destroy?
    create?
  end

  private
  
  def teacher_of?(classroom)
    return false unless teacher?
    classroom.teacher_id == user.id
  end
end
