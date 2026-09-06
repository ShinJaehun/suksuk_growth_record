class Admin::TeachersController < Admin::BaseController
  before_action :set_teacher, only: %i[edit update]
  before_action :set_status_teacher, only: %i[deactivate reactivate]

  def index
    prepare_school_filter
    @teacher_rows = teacher_rows
  end

  def new
    @teacher = User.new(role: :teacher)
    authorize @teacher
    load_school_assignment_form
  end

  def create
    attrs = teacher_params
    attrs[:email] = attrs[:email].presence
    attrs[:gender] = nil unless %w[male female].include?(attrs[:gender])
    @teacher = User.new(attrs.merge(role: :teacher))
    pool = avatar_keys_for_gender(@teacher.gender)
    @teacher.avatar_key = pool.sample unless pool.include?(@teacher.avatar_key)
    authorize @teacher

    school = selected_school
    classroom_id = selected_classroom_id(school)
    result =
      unless school_assignment_invalid?
        Teachers::SaveWithAssignment.call(
          teacher: @teacher,
          attributes: {},
          school: school,
          membership_grade: selected_membership_grade,
          classroom_id: classroom_id,
          actor: current_user
        )
      end

    if result&.success?
      expose_temporary_password(result)
      redirect_to admin_teachers_path,
                  notice: t('admin.teachers.create.success'),
                  status: :see_other
    else
      flash.now[:alert] = t('admin.teachers.create.failure')
      load_school_assignment_form
      render :new, formats: :html, status: :unprocessable_content
    end
  end

  def edit
    authorize @teacher
    load_edit_form
  end

  def update
    authorize @teacher, @teacher.teacher? ? :update? : :index?

    unless @teacher.teacher?
      @teacher.errors.add(:base, t('admin.teachers.errors.teacher_required'))
      load_edit_form
      render :edit, formats: :html, status: :unprocessable_content
      return
    end

    unless school_selection_submitted? && classroom_selection_submitted?
      @teacher.errors.add(:base, t('admin.teachers.errors.assignment_selection_required'))
      load_edit_form
      render :edit, formats: :html, status: :unprocessable_content
      return
    end

    school = selected_school
    classroom_id = selected_classroom_id(school)
    result =
      unless school_assignment_invalid?
        Teachers::SaveWithAssignment.call(
          teacher: @teacher,
          attributes: {},
          school: school,
          membership_grade: selected_membership_grade,
          classroom_id: classroom_id,
          actor: current_user
        )
      end

    if result&.success?
      redirect_to edit_admin_teacher_path(@teacher),
                  notice: t('admin.teachers.update.success'),
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

  def teacher_rows
    scope = policy_scope(User)
            .teacher
            .with_attached_avatar
            .includes(school_year: :school, assigned_classroom: { school_year: :school })
    scope = scope.where(active: @teacher_status == 'active') unless @teacher_status == 'all'

    if @selected_school
      scope = scope.joins(:school_year)
                   .where(school_years: { school_id: @selected_school.id })
    end

    scope.order(:created_at)
         .map do |teacher|
           school = teacher.annual_school

           {
             teacher: teacher,
             school_name: school&.name || t('admin.teachers.index.unassigned_school'),
             school_color_key: school&.color_key,
             school_role: teacher.school_role,
             school_role_label: teacher_school_role_label(teacher),
             classrooms: [teacher.assigned_classroom].compact
           }
    end
  end

  def prepare_school_filter
    @teacher_status = params[:status].presence_in(%w[active inactive all]) || 'active'
    @filter_schools = policy_scope(School).order(:name, :id).load
    @selected_school = @filter_schools.detect { |school| school.id == school_filter_id }
  end

  def school_filter_id
    value = params[:school_id].to_s
    return nil unless value.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def teacher_school_role_label(teacher)
    return t('admin.teachers.index.unassigned_role') if teacher.school_role.blank?

    t(teacher.school_manager? ? 'admin.teachers.index.manager' : 'admin.teachers.index.member')
  end

  def set_teacher
    @teacher = User.find(params[:id])
  end

  def set_status_teacher
    @teacher = User.teacher.find(params[:id])
  end

  def update_teacher_status(active)
    if @teacher.update(active: active, remember_created_at: nil)
      redirect_to edit_admin_teacher_path(@teacher),
                  notice: t(active ? 'teacher_status.reactivated' : 'teacher_status.deactivated'),
                  status: :see_other
    else
      @teacher.errors.add(:base, t('teacher_status.failure')) if @teacher.errors.empty?
      load_edit_form
      render :edit, formats: :html, status: :unprocessable_content
    end
  end

  def teacher_params
    params.require(:user).permit(:name, :email, :login_id, :gender, :avatar_key)
  end

  def avatar_keys_for_gender(gender)
    return User::TEACHER_MALE_AVATAR_KEYS if gender == 'male'
    return User::TEACHER_FEMALE_AVATAR_KEYS if gender == 'female'

    teacher_avatar_keys
  end

  def teacher_avatar_keys
    User.avatar_keys_for_role('teacher')
  end

  def selected_school
    return @selected_school if defined?(@selected_school)
    return nil if teacher_assignment_params[:school_id].blank?

    @selected_school = School.find_by(id: teacher_assignment_params[:school_id])
    if @selected_school&.active? ||
        @selected_school&.id == @teacher.annual_school&.id
      return @selected_school
    end

    @school_selection_invalid = true
    @teacher.errors.add(:base, t('admin.teachers.errors.school_not_found'))
    nil
  end

  def school_selection_invalid?
    @school_selection_invalid == true
  end

  def selected_classroom_id(school)
    raw_id = teacher_assignment_params[:classroom_id].to_s
    return nil if raw_id.blank?

    classroom = raw_id.match?(/\A[1-9]\d*\z/) ? Classroom.find_by(id: raw_id) : nil
    if classroom.nil?
      @classroom_selection_invalid = true
      @teacher.errors.add(:base, t('admin.teachers.errors.classroom_not_found'))
    elsif !school_selection_invalid? && school.nil?
      @classroom_selection_invalid = true
      @teacher.errors.add(:base, t('admin.teachers.errors.school_required_for_classrooms'))
    elsif school && classroom.school_year.school_id != school.id
      @classroom_selection_invalid = true
      @teacher.errors.add(:base, t('admin.teachers.errors.classroom_school_mismatch'))
    end
    raw_id.to_i
  end

  def selected_membership_grade
    value = teacher_assignment_params[:membership_grade].to_s
    return nil if value.blank?
    return value.to_i if value.match?(/\A[1-6]\z/)

    @classroom_selection_invalid = true
    @teacher.errors.add(:base, t('admin.teachers.errors.membership_grade_invalid'))
    nil
  end

  def school_assignment_invalid?
    school_selection_invalid? || @classroom_selection_invalid == true
  end

  def school_selection_submitted?
    teacher_assignment_params.key?(:school_id)
  end

  def classroom_selection_submitted?
    teacher_assignment_params.key?(:classroom_id)
  end

  def load_edit_form
    load_school_assignment_form
  end

  def load_school_assignment_form
    current_school_id = @teacher.annual_school&.id
    @schools = School.active.or(School.where(id: current_school_id)).order(:name, :id).load
    @classrooms_by_school = Classroom.joins(:school_year)
      .where(school_years: { school_id: @schools.map(&:id), status: "active" })
      .includes(:school_year)
      .order(:grade, :class_label, :id)
      .group_by { |classroom| classroom.school_year.school_id }
    load_selected_school
    @selected_classroom_id = teacher_assignment_params.key?(:classroom_id) ?
      teacher_assignment_params[:classroom_id].presence&.to_i : @teacher.assigned_classroom&.id
  end

  def load_selected_school
    @selected_school_id =
      if school_selection_submitted?
        teacher_assignment_params[:school_id].presence&.to_i
      else
        @teacher.annual_school&.id
      end
  end

  def teacher_assignment_params
    @teacher_assignment_params ||= params.permit(:school_id, :membership_grade, :classroom_id)
  end

  def expose_temporary_password(result)
    return if result.temporary_password.blank?

    flash[:temporary_password] = t(
      'admin.teachers.create.temporary_password',
      password: result.temporary_password
    )
  end

end
