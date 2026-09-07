class Users::ForcedPasswordsController < ApplicationController
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped
  skip_before_action :require_teacher_password_change
  before_action :authenticate_user!
  before_action :require_forced_teacher

  def edit; end

  def update
    attributes = password_params
    current_user.errors.add(:password, :blank) if attributes[:password].blank?

    if current_user.errors.empty? && current_user.update(attributes.merge(password_change_required: false))
      teacher = current_user
      reset_session
      sign_in(:user, teacher, force: true)
      redirect_to after_sign_in_path_for(teacher), notice: t("users.forced_passwords.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def require_forced_teacher
    return if current_user.teacher? && current_user.password_change_required?

    redirect_to root_path
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
