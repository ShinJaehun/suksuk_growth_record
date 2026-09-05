class ApplicationController < ActionController::Base
  STUDENT_SESSION_TTL = 20.minutes

  include Pundit::Authorization
  include Pagy::Method

  helper_method :navigation_context
  
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :expire_inactive_teacher_session
  before_action :expire_student_session_if_inactive

  def after_sign_in_path_for(resource_or_scope)
    return user_path(resource_or_scope) if resource_or_scope.is_a?(User) && resource_or_scope.student?

    role_landing_path_for(resource_or_scope)
  end

  rescue_from Pundit::NotAuthorizedError do
    respond_to do |format|
      format.html do
        redirect_to(root_path, alert: t("errors.not_authorized"))
      end
      format.json do
        render json: { ok: false, error: "not_authorized" }, status: :forbidden
      end
      format.any do
        head :forbidden
      end
    end
  end

  # 개발 시 권한 체크 누락 방지: index는 policy_scope, 그 외는 authorize 요구
  after_action :verify_authorized, unless: :skip_pundit_verify_authorized?
  after_action :verify_policy_scoped, if: :pundit_verify_policy_scoped?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name, :gender, :avatar_key])
  end


  private

  def navigation_context
    return {} unless request.format.html? && current_user
    return @navigation_context if defined?(@navigation_context)

    @navigation_context = { user: current_user }
    return @navigation_context unless current_user.active_teacher?

    school_membership = current_user.school_membership
    school = school_membership&.school
    active_school = school if school&.active?
    manager_membership =
      school_membership if active_school && school_membership.manager?

    @navigation_context.merge!(
      manager_membership: manager_membership,
      classrooms: manager_membership ? [] : teacher_nav_classrooms
    )
  end

  def teacher_nav_classrooms
    return [] unless current_user&.active_teacher?
    return @teacher_nav_classrooms if defined?(@teacher_nav_classrooms)

    classroom = current_user.assigned_classroom
    @teacher_nav_classrooms = classroom&.active? && classroom.school.active? ? [classroom] : []
  end

  def expire_inactive_teacher_session
    return unless current_user&.teacher? && current_user.inactive?

    sign_out(:user)
    redirect_to new_user_session_path, alert: t("devise.failure.inactive")
  end

  def expire_student_session_if_inactive
    return unless current_user&.student?
    return if student_session_ttl_exempt_controller?

    classroom_id = session[:student_login_classroom_id]
    if classroom_id.present? && !active_student_membership?(classroom_id)
      sign_out(:user)
      return redirect_to student_session_timeout_redirect_path(classroom_id),
        alert: "사용 시간이 지나 자동으로 로그아웃되었습니다. 다시 로그인해 주세요."
    end

    now = Time.current.to_i
    last_seen_at = session[:student_last_seen_at]

    unless last_seen_at.present?
      session[:student_last_seen_at] = now
      return
    end

    if now - last_seen_at.to_i > STUDENT_SESSION_TTL.to_i
      classroom_id = session[:student_login_classroom_id]
      sign_out(:user)
      redirect_to student_session_timeout_redirect_path(classroom_id),
        alert: "사용 시간이 지나 자동으로 로그아웃되었습니다. 다시 로그인해 주세요."
    else
      session[:student_last_seen_at] = now
    end
  end

  def active_student_membership?(classroom_id)
    ClassroomMembership.joins(classroom: :school).merge(Classroom.active).merge(School.active).exists?(
      classroom_id: classroom_id,
      user_id: current_user.id,
      role: "student",
      status: "active"
    )
  end

  def student_session_ttl_exempt_controller?
    devise_controller? || is_a?(StudentSessionsController)
  end

  def student_session_timeout_redirect_path(classroom_id)
    return new_student_session_path if classroom_id.blank?
    classroom = Classroom.find_by(id: classroom_id)
    return new_student_session_path unless classroom

    public_student_login_path(student_login_token: classroom.student_login_token)
  end

  def role_landing_path
    role_landing_path_for(current_user)
  end

  def role_landing_path_for(user)
    return user_path(user) if user.student?
    return schools_path if user.admin?

    managed_membership =
      if user.school_membership&.manager? && user.school_membership.school.active?
        user.school_membership
      end
    return school_path(managed_membership.school) if managed_membership

    regular_teacher_landing_path_for(user)
  end

  def regular_teacher_landing_path_for(user)
    classroom = user.assigned_classroom
    classroom&.active? && classroom.school.active? ? classroom_path(classroom) : classrooms_path
  end

  # index가 아닌 액션에서는 authorize 검증, Devise 컨트롤러는 제외
  def skip_pundit_verify_authorized?
    devise_controller? || action_name == "index"
  end

  # index 액션에서만 policy_scope 검증, Devise 컨트롤러는 제외
  def pundit_verify_policy_scoped?
    !devise_controller? && action_name == "index"
  end
end
