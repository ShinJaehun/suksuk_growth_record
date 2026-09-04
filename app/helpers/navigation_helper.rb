module NavigationHelper
  def primary_navigation_items(context)
    user = context[:user]
    return [] unless user

    if user.admin?
      [
        navigation_item("navigation.school_management", schools_path),
        navigation_item("navigation.classrooms", classrooms_path),
        (navigation_item("navigation.teacher_management", teachers_path) if can_manage_teachers?)
      ].compact
    elsif context[:manager_membership]
      [
        navigation_item("navigation.school_operations", school_path(context[:manager_membership].school)),
        navigation_item("navigation.classrooms", classrooms_path),
        navigation_item("navigation.teacher_management", teachers_path)
      ]
    elsif user.teacher?
      []
    elsif user.student?
      [navigation_item("navigation.my_page", user_path(user))]
    else
      []
    end
  end

  def teacher_classroom_navigation(context)
    return unless context[:user]&.teacher? && !context[:manager_membership]

    classrooms = context.fetch(:classrooms, [])
    {
      mode: classrooms.none? ? :index : (classrooms.one? ? :single : :multiple),
      classrooms: classrooms
    }
  end

  def management_navigation_groups
    []
  end

  def navigation_account(context)
    user = context[:user]
    return unless user

    {
      user: user,
      display_name: user.name.presence || user.email,
      edit_path: (edit_user_registration_path unless user.student?),
      sign_out_label: t(user.student? ? "navigation.account.finish" : "navigation.account.sign_out"),
      sign_out_path: user.student? ? destroy_student_session_path : destroy_user_session_path
    }
  end

  # global admin과 학교 대표 선생님만 교사 관리 화면 접근 가능
  def can_manage_teachers?
    return false unless current_user

    TeacherManagementPolicy.new(current_user, User).access?
  end

  private

  def navigation_item(label_key, path)
    { label: t(label_key), path: path }
  end
end
