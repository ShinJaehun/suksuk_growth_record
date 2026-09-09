class StudentSessionsController < ApplicationController
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def new
    return unless load_classroom

    set_student_session_form_url
    load_students if @classroom
  end

  def create
    return unless load_classroom

    set_student_session_form_url
    load_students

    student = find_student_for_pin_login
    attempt_limiter = student_pin_attempt_limiter(student)
    if attempt_limiter&.blocked?
      flash.now[:alert] = t('student_sessions.throttled')
      return render :new, status: :unprocessable_content
    end

    if student&.student_pin_configured? && student.authenticate_student_pin(params[:student_pin].to_s)
      attempt_limiter&.reset
      classroom_id = @classroom.id

      sign_out(:user) if user_signed_in?
      reset_session

      session[:student_id] = student.id
      session[:student_login_classroom_id] = classroom_id
      session[:student_last_seen_at] = Time.current.to_i
      redirect_to student_growth_record_path, notice: t('student_sessions.signed_in')
    else
      throttled = attempt_limiter&.record_failure
      flash.now[:alert] = throttled ? t('student_sessions.throttled') : t('student_sessions.invalid')
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    clear_student_session
    redirect_to new_student_session_path, notice: t('student_sessions.signed_out')
  end

  private

  def load_classroom
    @classroom =
      if params[:student_login_token].present?
        classroom = Classroom.find_by(student_login_token: params[:student_login_token])
        return render_invalid_link unless classroom&.active? && classroom.school_year&.active? &&
          classroom.school_year.school.active?

        classroom
      end

    true
  end

  def render_invalid_link
    render :invalid_link, status: :not_found
    false
  end

  def set_student_session_form_url
    @student_session_form_url =
      if params[:student_login_token].present?
        public_student_login_path(student_login_token: params[:student_login_token])
      elsif @classroom
        public_student_login_path(student_login_token: @classroom.student_login_token)
      else
        new_student_session_path
      end
  end

  def load_students
    @students = @classroom ? Student.active.where(classroom: @classroom).order(:name) : Student.none
  end

  def find_student_for_pin_login
    return nil unless @classroom

    student = Student.active.find_by(id: params[:student_id], classroom_id: @classroom.id)

    student
  end

  def student_pin_attempt_limiter(student)
    return nil unless @classroom && student

    StudentPinAttemptLimiter.new(
      classroom_id: @classroom.id,
      student_id: student.id,
      pin_digest: student.student_pin_digest,
      remote_ip: request.remote_ip
    )
  end
end
