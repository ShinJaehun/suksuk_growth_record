class StudentProfileController < ApplicationController
  before_action :require_student_session

  def show
    authorize current_student, :show?
    redirect_to student_growth_path(tab: "today")
  end

  def edit
    authorize current_student, :manage_own_student_pin?
  end

  def update
    authorize current_student, :manage_own_student_pin?

    pin = student_params[:student_pin].to_s
    confirmation = student_params[:student_pin_confirmation].to_s
    validate_pin(pin, confirmation)

    if current_student.errors.empty? && current_student.update(student_params)
      redirect_to student_profile_path,
        notice: t("students.edit.self_pin.success"),
        status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def require_student_session
    return if current_student

    redirect_to new_student_session_path, alert: t("student_sessions.invalid")
  end

  def student_params
    params.require(:student).permit(:student_pin, :student_pin_confirmation)
  end

  def validate_pin(pin, confirmation)
    if pin.blank?
      current_student.errors.add(:base, t("students.edit.self_pin.errors.blank"))
    elsif !pin.match?(/\A\d{4}\z/)
      current_student.errors.add(:base, t("students.edit.self_pin.errors.invalid"))
    elsif pin != confirmation
      current_student.errors.add(:base, t("students.edit.self_pin.errors.confirmation"))
    end
  end
end
