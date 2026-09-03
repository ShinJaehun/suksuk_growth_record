class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [:show]

  def show
    authorize @user, :show?
    redirect_to(role_landing_path) and return unless @user.student?
    redirect_student_self_to_classroom_context! and return if @user.student? && current_user == @user
    redirect_to_managed_student_page! and return if @user.student? && current_user != @user

    @visible_classrooms = @user.classrooms.order(created_at: :asc)
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def redirect_to_managed_student_page!
    classroom = managed_page_classroom_for(@user)
    raise ActiveRecord::RecordNotFound unless classroom

    redirect_to classroom_student_path(classroom, @user)
  end

  def managed_page_classroom_for(user)
    return user.classrooms.order(created_at: :asc).first if current_user.admin?
    return teacher_managed_classroom_for(user) if current_user.active_teacher?

    nil
  end

  def redirect_student_self_to_classroom_context!
    classroom = student_self_page_classroom_for(@user)
    return unless classroom

    redirect_to classroom_student_path(classroom, @user)
  end

  def student_self_page_classroom_for(user)
    session_classroom = session_classroom_for(user)
    return session_classroom if session_classroom

    active_student_membership_classroom_for(user)
  end

  def session_classroom_for(user)
    classroom_id = session[:student_login_classroom_id]
    return nil if classroom_id.blank?

    active_student_classrooms_for(user).find_by(id: classroom_id)
  end

  def active_student_classrooms_for(user)
    Classroom
      .joins(:classroom_memberships)
      .where(classroom_memberships: { user_id: user.id, role: "student", status: "active" })
      .distinct
  end

  def active_student_membership_classroom_for(user)
    ClassroomMembership
      .student
      .active
      .includes(:classroom)
      .find_by(user_id: user.id)
      &.classroom
  end

  def teacher_managed_classroom_for(user)
    Classroom
      .joins(:classroom_memberships)
      .where(classroom_memberships: { user_id: current_user.id, role: "teacher" })
      .where(id: user.classroom_ids)
      .order(created_at: :asc)
      .first
  end

end
