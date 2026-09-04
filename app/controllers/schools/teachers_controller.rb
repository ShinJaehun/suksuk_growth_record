class Schools::TeachersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_school
  before_action :authorize_school_teacher_management
  before_action :set_teacher, only: %i[edit update deactivate reactivate]

  def index
    @teacher_status = params[:status].presence_in(%w[active inactive all]) || "active"
    @teacher_rows = teacher_rows
  end

  def new
    @teacher = User.new(role: :teacher)
    load_new_form
  end

  def create
    attrs = teacher_params
    attrs[:gender] = nil unless %w[male female].include?(attrs[:gender])
    @teacher = User.new(attrs.merge(role: :teacher))
    pool = avatar_keys_for_gender(@teacher.gender)
    @teacher.avatar_key = pool.sample unless pool.include?(@teacher.avatar_key)

    classroom_id = selected_classroom_id
    assignments_invalid = classroom_assignments_invalid?
    result =
      unless assignments_invalid
        Teachers::SaveWithAssignment.call(
          teacher: @teacher,
          attributes: {},
          school: @school,
          membership_grade: selected_membership_grade,
          classroom_id: classroom_id
        )
      end

    if !assignments_invalid && result.success?
      redirect_to school_teachers_path(@school),
        notice: t("schools.teachers.create.success"),
        status: :see_other
    else
      load_new_form
      flash.now[:alert] = t("schools.teachers.create.failure")
      render :new, formats: :html, status: :unprocessable_content
    end
  end

  def edit
    load_edit_form
  end

  def update
    selected_classroom_id

    result =
      unless classroom_assignments_invalid?
        Teachers::SaveWithAssignment.call(
          teacher: @teacher,
          attributes: {},
          school: @school,
          membership_grade: selected_membership_grade,
          classroom_id: selected_classroom_id
        )
      end

    if classroom_assignments_invalid?
      load_edit_form
      render :edit, formats: :html, status: :unprocessable_content
    elsif result.success?
      redirect_to school_teachers_path(@school),
        notice: t("schools.teachers.update.success"),
        status: :see_other
    else
      load_edit_form
      render :edit, formats: :html, status: :unprocessable_content
    end
  end

  def deactivate
    authorize @teacher, :deactivate_teacher?
    update_teacher_status(false)
  end

  def reactivate
    authorize @teacher, :reactivate_teacher?
    update_teacher_status(true)
  end

  private

  def set_school
    @school = policy_scope(School).find(params[:school_id])
  end

  def authorize_school_teacher_management
    authorize @school, :manage_teachers?
  end

  def set_teacher
    membership = @school.school_memberships.includes(:user).find_by!(user_id: params[:id])
    @school_membership = membership
    @teacher = membership.user
    raise ActiveRecord::RecordNotFound unless @teacher.teacher?
  end

  def teacher_rows
    @school.school_memberships
      .includes(user: [{ avatar_attachment: :blob }, :assigned_classroom])
      .order(:role, :id)
      .select { |membership| membership.user.teacher? }
      .select { |membership| @teacher_status == "all" || membership.user.active? == (@teacher_status == "active") }
      .map do |membership|
        teacher = membership.user
        classrooms = school_teacher_classrooms(teacher)

        {
          teacher: teacher,
          school_color_key: @school.color_key,
          school_role: membership.role,
          school_role_label: teacher_school_role_label(membership),
          classrooms: classrooms
        }
      end
  end

  def school_teacher_classrooms(teacher)
    [teacher.assigned_classroom].compact.select { |classroom| classroom.school_id == @school.id }
  end

  def teacher_school_role_label(membership)
    t(membership.manager? ? "admin.teachers.index.manager" : "admin.teachers.index.member")
  end

  def teacher_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :gender, :avatar_key)
  end

  def update_teacher_status(active)
    if @teacher.update(active: active, remember_created_at: nil)
      redirect_to school_teachers_path(@school, status: params[:status]),
        notice: t(active ? "teacher_status.reactivated" : "teacher_status.deactivated"),
        status: :see_other
    else
      redirect_to school_teachers_path(@school), alert: t("teacher_status.failure"), status: :see_other
    end
  end

  def avatar_keys_for_gender(gender)
    return User::TEACHER_MALE_AVATAR_KEYS if gender == "male"
    return User::TEACHER_FEMALE_AVATAR_KEYS if gender == "female"

    teacher_avatar_keys
  end

  def teacher_avatar_keys
    User.avatar_keys_for_role("teacher")
  end

  def load_new_form
    @classrooms = @school.classrooms.order(:grade, :name, :id).load
    @selected_classroom_id = nil unless defined?(@selected_classroom_id)
  end

  def selected_classroom_id
    return @selected_classroom_id if defined?(@selected_classroom_id)

    raw_id = params[:classroom_id].to_s
    return @selected_classroom_id = nil if raw_id.blank?

    classroom = raw_id.match?(/\A[1-9]\d*\z/) ? @school.classrooms.find_by(id: raw_id) : nil
    unless classroom
      @classroom_assignments_invalid = true
      @teacher.errors.add(:base, t("schools.teachers.errors.classroom_not_found"))
    end
    @selected_classroom_id = raw_id.to_i
  end

  def selected_membership_grade
    value = params[:membership_grade].to_s
    return nil if value.blank?
    return value.to_i if value.match?(/\A[1-6]\z/)

    @classroom_assignments_invalid = true
    @teacher.errors.add(:base, t("admin.teachers.errors.membership_grade_invalid"))
    nil
  end

  def classroom_assignments_invalid?
    @classroom_assignments_invalid == true
  end

  def load_edit_form
    @classrooms = @school.classrooms.order(:grade, :name, :id).load
    @selected_classroom_id = params.key?(:classroom_id) ? selected_classroom_id : @teacher.assigned_classroom&.id
  end

end
