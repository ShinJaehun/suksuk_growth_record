class Classrooms::ShowContext
  def initialize(classroom:)
    @classroom = classroom
  end

  def student_memberships
    @student_memberships ||= @classroom.classroom_memberships
                                       .student
                                       .active
                                       .in_roster_order
                                       .preload(user: { avatar_attachment: :blob })
  end

  def homeroom_teacher
    teacher = @classroom.teacher
    teacher if teacher&.active?
  end
end
