class ClassroomStudentPolicy < ApplicationPolicy
  def create?
    return false unless record.classroom&.active? && record.classroom.school&.active?
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
