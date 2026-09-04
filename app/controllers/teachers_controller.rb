class TeachersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_teacher_management!
  before_action :set_teacher, only: %i[edit update deactivate reactivate]

  def index
    prepare_index
  end

  def new
    @teacher = User.new(role: :teacher)
    authorize @teacher, :create?, policy_class: TeacherManagementPolicy
    prepare_form
  end

  def create
    @teacher = User.new(normalized_profile_attributes(create_params).merge(role: :teacher))
    authorize @teacher, :create?, policy_class: TeacherManagementPolicy
    school = managed_school
    classroom_ids = selected_active_classroom_ids(school)
    result = save_teacher(school, classroom_ids, attributes: {}) unless assignment_invalid?

    if result&.success?
      redirect_to teachers_path, notice: t('admin.teachers.create.success'), status: :see_other
    else
      prepare_form
      flash.now[:alert] = t('admin.teachers.create.failure')
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @teacher, :update_profile?, policy_class: TeacherManagementPolicy
    prepare_form
  end

  def update
    authorize @teacher, :update_profile?, policy_class: TeacherManagementPolicy
    school = managed_school
    classroom_ids = selected_active_classroom_ids(school) + preserved_inactive_classroom_ids
    attributes = normalized_profile_attributes(update_params, current_avatar_key: @teacher.avatar_key)
    result = save_teacher(school, classroom_ids.uniq, attributes: attributes) unless assignment_invalid?

    if result&.success?
      redirect_to teachers_path, notice: t('admin.teachers.update.success'), status: :see_other
    else
      prepare_form
      render :edit, status: :unprocessable_content
    end
  end

  def deactivate
    authorize @teacher, :deactivate_teacher?
    update_status(false)
  end

  def reactivate
    authorize @teacher, :reactivate_teacher?
    update_status(true)
  end

  private

  def authorize_teacher_management!
    authorize User, :access?, policy_class: TeacherManagementPolicy
  end

  def set_teacher
    @teacher = teacher_management_scope.find(params[:id])
  end

  def prepare_index
    @teacher_status = params[:status].presence_in(%w[active inactive all]) || 'active'
    @filter_schools = manageable_schools
    @selected_school = if current_user.admin?
                         @filter_schools.find do |school|
                           school.id == school_filter_id
                         end
                       else
                         manager_school
                       end
    scope = teacher_management_scope.with_attached_avatar.includes(school_membership: :school,
                                                                   classroom_memberships: :classroom)
    scope = scope.where(active: @teacher_status == 'active') unless @teacher_status == 'all'
    if @selected_school
      scope = scope.joins(:school_membership).where(school_memberships: { school_id: @selected_school.id })
    end
    @teacher_rows = scope.order(:created_at).map { |teacher| teacher_row(teacher) }
  end

  def prepare_form
    @schools = manageable_schools
    @selected_school_id = managed_school&.id
    @classrooms_by_school = @schools.index_with { |school| school.classrooms.active.order(:grade, :name, :id).load }
    @selected_classroom_ids ||= @teacher.persisted? ? @teacher.classroom_memberships.teacher.pluck(:classroom_id) : []
  end

  def manageable_schools
    @manageable_schools ||=
      if current_user.admin?
        current_school_id = @teacher&.school_membership&.school_id
        policy_scope(School).active
                            .or(School.where(id: current_school_id))
                            .order(:name, :id)
                            .load
      else
        [manager_school]
      end
  end

  def manager_school
    current_user.school_membership&.school
  end

  def managed_school
    return manager_school unless current_user.admin?
    return @managed_school if defined?(@managed_school)

    unless params.key?(:school_id)
      @managed_school = @teacher.school_membership&.school if @teacher&.persisted?
      return @managed_school
    end

    id = params[:school_id].to_s
    @managed_school = manageable_schools.find { |school| school.id == id.to_i } if id.match?(/\A[1-9]\d*\z/)
  end

  def selected_active_classroom_ids(school)
    raw_ids = Array(params[:classroom_ids]).reject(&:blank?)
    valid_ids = raw_ids.filter_map { |value| value.to_i if value.to_s.match?(/\A[1-9]\d*\z/) }.uniq
    classrooms = school ? school.classrooms.active.where(id: valid_ids) : Classroom.none
    @selected_classroom_ids = valid_ids
    if valid_ids.size != raw_ids.size || classrooms.count != valid_ids.size
      @assignment_invalid = true
      @teacher.errors.add(:base, t('admin.teachers.errors.classroom_not_found'))
    end
    valid_ids
  end

  def preserved_inactive_classroom_ids
    @teacher.classroom_memberships.teacher
            .joins(:classroom)
            .merge(Classroom.inactive)
            .where(classrooms: { school_id: managed_school&.id })
            .pluck(:classroom_id)
  end

  def assignment_invalid?
    if managed_school.nil? && !current_user.admin?
      @teacher.errors.add(:base, t('admin.teachers.errors.school_not_found'))
      @assignment_invalid = true
    end
    @assignment_invalid == true
  end

  def save_teacher(school, classroom_ids, attributes:)
    Teachers::SaveWithAssignments.call(
      teacher: @teacher,
      attributes: attributes,
      school: school,
      classroom_ids: classroom_ids,
      assignment_scope: current_user.admin? ? :all : :school
    )
  end

  def create_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :gender, :avatar_key)
  end

  def update_params
    params.require(:user).permit(:name, :email, :gender, :avatar_key)
  end

  def normalized_profile_attributes(permitted_params, current_avatar_key: nil)
    attributes = permitted_params.to_h.symbolize_keys
    attributes[:gender] = nil if attributes.key?(:gender) && !%w[male female].include?(attributes[:gender])
    gender = attributes.key?(:gender) ? attributes[:gender] : @teacher&.gender
    avatar_key = attributes[:avatar_key].presence || current_avatar_key
    pool = User.avatar_keys_for(gender).presence || User.avatar_keys_for_role('teacher')
    attributes[:avatar_key] = pool.sample unless pool.include?(avatar_key)
    attributes
  end

  def teacher_management_scope
    policy_scope(User, policy_scope_class: TeacherManagementPolicy::Scope)
  end

  def update_status(active)
    if @teacher.update(active: active, remember_created_at: nil)
      redirect_to edit_teacher_path(@teacher),
                  notice: t(active ? 'teacher_status.reactivated' : 'teacher_status.deactivated'), status: :see_other
    else
      redirect_to edit_teacher_path(@teacher), alert: t('teacher_status.failure'), status: :see_other
    end
  end

  def school_filter_id
    value = params[:school_id].to_s
    value.to_i if value.match?(/\A[1-9]\d*\z/)
  end

  def teacher_row(teacher)
    membership = teacher.school_membership
    classrooms = teacher.classroom_memberships.select(&:teacher?).filter_map(&:classroom).sort_by do |classroom|
      [classroom.grade, classroom.name, classroom.id]
    end
    { teacher: teacher, school: membership&.school, role: membership&.role, classrooms: classrooms }
  end
end
