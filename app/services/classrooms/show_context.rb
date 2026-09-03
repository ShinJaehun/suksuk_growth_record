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
    @homeroom_teachers ||= User.teacher.active
      .joins(:classroom_memberships)
      .where(classroom_memberships: { classroom_id: @classroom.id, role: "teacher" })
      .with_attached_avatar
      .order(:name, :id)
  end

end
