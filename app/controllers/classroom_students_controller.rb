class ClassroomStudentsController < ApplicationController
  helper_method :return_to_context, :member_status_context, :members_return_to?,
    :managed_student_navigation_params, :managed_student_back_path

  before_action :authenticate_user!
  before_action :set_classroom
  before_action :authorize_manage!, only: %i[new create]
  before_action :set_student, only: %i[show edit update destroy deactivate reactivate]

  def new
    @student = @classroom.students.build(active: true)
    render_form
  end

  def create
    attrs = student_params
    attrs[:avatar_key] = pick_avatar_key(attrs[:gender]) if attrs[:avatar_key].blank?
    @student = @classroom.students.build(attrs.merge(active: true))
    validate_new_gender
    validate_new_pin
    validate_student_avatar(@student, attrs)

    if @student.errors.empty? && save_student
      respond_to do |format|
        format.html { redirect_to create_success_path, notice: t("students.create.success"), status: :see_other }
        format.turbo_stream do
          flash.now[:notice] = t("students.create.success")
          members_return_to? ? load_members_students : load_classroom_students
          render members_return_to? ? :create_for_members : :create, layout: "application"
        end
      end
    else
      respond_to do |format|
        format.html { render_form(status: :unprocessable_content, alert: student_error_message) }
        format.turbo_stream do
          flash.now[:alert] = student_error_message
          render :create_error, layout: "application", status: :unprocessable_content
        end
      end
    end
  end

  def show
    authorize @classroom, :manage_growth?
    @can_manage_student = policy(@student).manage?
    @record = @student.daily_growth_records
      .where(classroom: @classroom)
      .includes(:daily_growth_scores, daily_virtue_configuration: :items)
      .find_by(recorded_on: Time.zone.today)
    @score_rows = score_rows(@record)
  end

  def edit
    authorize @student, :manage?
    @student_avatar_keys = Student::AVATAR_KEYS
  end

  def update
    authorize @student, :manage?
    attrs = student_params
    attrs.delete(:student_pin) if attrs[:student_pin].blank?
    normalize_managed_avatar!(attrs)
    validate_managed_avatar(attrs)

    if @student.errors.empty? && @student.update(attrs)
      redirect_to edit_classroom_student_path(@classroom, @student, managed_student_navigation_params),
        notice: t("students.edit.success")
    else
      @student_avatar_keys = Student::AVATAR_KEYS
      render :edit, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotUnique
    @student.errors.add(:student_number, t("students.create.errors.student_number_taken", number: attrs[:student_number]))
    @student_avatar_keys = Student::AVATAR_KEYS
    render :edit, status: :unprocessable_content
  end

  def destroy
    deactivate
  end

  def deactivate
    authorize @student, :manage?
    @student.update!(active: false)
    redirect_to classroom_members_path(@classroom), notice: t("students.deactivate.success"), status: :see_other
  end

  def reactivate
    authorize @student, :manage?
    error = nil
    @classroom.with_lock do
      @student.with_lock do
        unless operational_classroom?
          error = t("errors.not_authorized")
          next
        end
        if @classroom.active_students_count >= Classroom::MAX_ACTIVE_STUDENTS
          error = t("students.reactivate.too_many", count: Classroom::MAX_ACTIVE_STUDENTS)
          next
        end
        @student.update!(active: true)
      end
    end
    redirect_to classroom_members_path(@classroom),
      **(error ? { alert: error } : { notice: t("students.reactivate.success") }), status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to classroom_members_path(@classroom),
      alert: t("students.reactivate.active_membership_conflict"), status: :see_other
  end

  private

  def set_classroom = @classroom = Classroom.find(params[:classroom_id])
  def set_student = @student = @classroom.students.find(params[:id])
  def authorize_manage! = authorize(@classroom, :manage_members?)

  def score_rows(record)
    return [] unless record

    scores_by_virtue_id = record.daily_growth_scores.index_by(&:virtue_id)
    record.daily_virtue_configuration.items.filter_map do |item|
      score = scores_by_virtue_id[item.virtue_id]
      { name: item.name, value: score.score } if score
    end
  end

  def student_params
    params.require(:student).permit(:name, :student_number, :student_pin, :gender, :avatar_key)
  end

  def validate_new_gender
    return if Student::GENDERS.include?(@student.gender)

    @student.errors.add(:gender, t("students.create.errors.gender_required"))
  end

  def validate_new_pin
    return if @student.student_pin.to_s.match?(/\A\d{4}\z/)
    @student.errors.add(:student_pin, t("students.create.errors.invalid_pin"))
  end

  def save_student
    saved = false
    @classroom.with_lock do
      if @classroom.active_students_count >= Classroom::MAX_ACTIVE_STUDENTS
        @student.errors.add(:base, t("students.bulk_create.errors.too_many", count: Classroom::MAX_ACTIVE_STUDENTS))
        next
      end
      @student.save!
      saved = true
    end
    saved
  rescue ActiveRecord::RecordInvalid
    false
  rescue ActiveRecord::RecordNotUnique
    @student.errors.add(:student_number, t("students.create.errors.student_number_taken", number: @student.student_number))
    false
  end

  def operational_classroom?
    @classroom.active? && @classroom.school_year.active? && @classroom.school_year.school.active?
  end

  def pick_avatar_key(gender, excluding: nil)
    pool = Student.avatar_keys_for(gender)
    return nil if pool.empty?

    used_scope = @classroom.students.where.not(avatar_key: nil)
    used_scope = used_scope.where.not(id: excluding.id) if excluding
    available = pool - used_scope.distinct.pluck(:avatar_key)
    available.sample || pool.sample
  end

  def validate_student_avatar(student, attrs)
    return if attrs[:gender].blank? || attrs[:avatar_key].blank?
    return if Student.avatar_keys_for(attrs[:gender]).include?(attrs[:avatar_key])

    student.errors.add(:avatar_key, t("students.create.errors.invalid_avatar"))
  end

  def normalize_managed_avatar!(attrs)
    return unless attrs[:gender].present? && attrs[:gender] != @student.gender
    return unless attrs[:avatar_key].blank? || attrs[:avatar_key] == @student.avatar_key

    attrs[:avatar_key] = pick_avatar_key(attrs[:gender], excluding: @student)
  end

  def validate_managed_avatar(attrs)
    avatar_key = attrs[:avatar_key]
    return if avatar_key.blank?

    target_gender = attrs[:gender].presence || @student.gender
    return if avatar_key == @student.avatar_key && target_gender == @student.gender
    return if Student.avatar_keys_for(target_gender).include?(avatar_key)

    @student.errors.add(:avatar_key, t("students.create.errors.invalid_avatar"))
  end

  def render_form(status: :ok, alert: nil)
    flash.now[:alert] = alert if alert
    respond_to do |format|
      format.html { render partial: "classroom_students/form", locals: { classroom: @classroom, student: @student, return_to: return_to_context }, status: }
      format.turbo_stream { render partial: "classroom_students/form", locals: { classroom: @classroom, student: @student, return_to: return_to_context }, status: }
    end
  end

  def student_error_message
    @student.errors.full_messages.to_sentence.presence || t("students.create.failure_fallback")
  end

  def load_members_students
    base = @classroom.students
    counts = base.group(:active).count
    @member_status = "active"
    @student_member_counts = { "active" => counts.fetch(true, 0), "inactive" => counts.fetch(false, 0) }
    @student_member_counts["all"] = @student_member_counts.values.sum
    @students = base.active.in_roster_order
  end

  def load_classroom_students = @students = @classroom.students.active.in_roster_order
  def return_to_context = params[:return_to].presence_in(%w[members])
  def member_status_context = params[:status].to_s.presence_in(%w[active inactive all]) || "active"
  def members_return_to? = return_to_context == "members"
  def managed_student_navigation_params
    return {} unless members_return_to?

    { return_to: "members" }.tap do |navigation_params|
      navigation_params[:status] = member_status_context unless member_status_context == "active"
    end
  end

  def managed_student_back_path
    return classroom_student_path(@classroom, @student) unless members_return_to?
    return classroom_members_path(@classroom) if member_status_context == "active"

    classroom_members_path(@classroom, status: member_status_context)
  end
  def create_success_path = members_return_to? ? classroom_members_path(@classroom) : classroom_path(@classroom)
end
