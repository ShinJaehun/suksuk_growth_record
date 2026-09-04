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

  def students
    @students ||= User.where(id: student_memberships.map(&:user_id))
  end

  def homeroom_teachers
    @homeroom_teachers ||= [@classroom.teacher].compact.select(&:active?)
  end

end
