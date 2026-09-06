module ClassroomsHelper
  def classroom_display_name(classroom)
    grade_label = "#{classroom.grade}학년" if classroom.grade
    [grade_label, classroom_label(classroom)].compact.join(" ")
  end

  def classroom_label(classroom)
    "#{classroom.class_label}반"
  end
end
