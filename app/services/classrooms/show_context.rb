class Classrooms::ShowContext
  def initialize(classroom:)
    @classroom = classroom
  end

  def students
    @students ||= @classroom.students.active.in_roster_order
  end

  def homeroom_teacher
    teacher = @classroom.teacher
    teacher if teacher&.active?
  end
end
