class Classrooms::IndexContext
  def initialize(classrooms_scope:)
    @classrooms_scope = classrooms_scope
  end

  def classrooms
    @classrooms ||= @classrooms_scope
                    .includes(school_year: :school, teacher: { avatar_attachment: :blob })
                    .order(:grade, created_at: :desc)
  end

  def teachers
    @teachers ||= classrooms.to_h do |classroom|
      teacher = classroom.teacher
      [classroom.id, teacher&.active? ? teacher : nil]
    end
  end

  def student_counts
    @student_counts ||= Student.active
                        .where(classroom_id: classroom_ids)
                        .group(:classroom_id)
                        .count
  end

  def student_previews
    return @student_previews if defined?(@student_previews)
    return @student_previews = {} if classroom_ids.empty?

    ranked_ids = Student.from(
      Student.active.where(classroom_id: classroom_ids).select(
        "students.id, students.classroom_id, " \
        "ROW_NUMBER() OVER (PARTITION BY students.classroom_id ORDER BY students.created_at ASC, students.id ASC) AS preview_position"
      ), :students
    ).where("preview_position <= 5").pluck(:id)
    @student_previews = Student.where(id: ranked_ids).order(:classroom_id, :created_at, :id).group_by(&:classroom_id)
  end

  private

  def classroom_ids
    @classroom_ids ||= classrooms.map(&:id)
  end

end
