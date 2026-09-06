class Classrooms::MembersController < ApplicationController
  MEMBER_STATUS_FILTERS = %w[active inactive all].freeze

  before_action :authenticate_user!
  before_action :set_classroom

  def show
    authorize @classroom, :manage_members?
    load_members_page!
  end

  def edit_student_names
    authorize @classroom, :manage_members?
    @member_status = member_status_filter
    load_students_for_roster

    render :edit_student_names, layout: false
  end

  def update_student_names
    authorize @classroom, :manage_members?

    @member_status = member_status_filter
    load_students_for_roster
    result = ClassroomStudents::RosterUpdate.call(
      classroom: @classroom,
      students: @roster_students,
      rows: params.fetch(:students, {})
    )

    unless result.success?
      @roster_students = result.students
      @submitted_student_roster = result.rows
      @student_roster_errors_by_student_id = result.row_errors
      return render_student_roster_errors(result.error_key)
    end

    respond_to do |format|
      format.html do
        redirect_to members_redirect_path,
          notice: t("students.members.update_names.success"),
          status: :see_other
      end
      format.turbo_stream do
        load_members_page!
        flash.now[:notice] = t("students.members.update_names.success")
        render :update_student_names, layout: false
      end
    end
  end

  def edit_student_pin
    authorize @classroom, :manage_members?
    @student_pin = ""

    render :edit_student_pin, layout: false
  end

  def update_student_pin
    authorize @classroom, :manage_members?

    @student_pin = params[:student_pin].to_s
    @student_pin_error = student_pin_error_message(@student_pin)
    return render_student_pin_error if @student_pin_error.present?

    students = @classroom.students.active.order(:created_at, :id).to_a
    if students.empty?
      @student_pin_error = t("students.members.pin_reset.no_active_students")
      return render_student_pin_error
    end

    ApplicationRecord.transaction do
      students.each { |student| student.update!(student_pin: @student_pin) }
    end

    respond_to do |format|
      format.html do
        redirect_to classroom_members_path(@classroom),
          notice: t("students.members.pin_reset.success", count: students.size),
          status: :see_other
      end
      format.turbo_stream do
        flash.now[:notice] = t("students.members.pin_reset.success", count: students.size)
        render :update_student_pin, layout: false
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    @student_pin_error = t(
      "students.members.pin_reset.failure",
      detail: e.record.errors.full_messages.to_sentence
    )
    render_student_pin_error
  end

  private

  def set_classroom
    @classroom = Classroom.find(params[:classroom_id])
  end

  def load_students
    @member_status = member_status_filter
    base_scope = @classroom.students
    status_counts = base_scope.group(:active).count
    @student_member_counts = {
      "active" => status_counts.fetch(true, 0),
      "inactive" => status_counts.fetch(false, 0)
    }
    @student_member_counts["all"] = @student_member_counts.values.sum

    @students =
      if @member_status == "all"
        base_scope.order(active: :desc).in_roster_order
      else
        base_scope.where(active: @member_status == "active").in_roster_order
      end
  end

  def load_members_page!
    load_students
  end

  def member_status_filter
    params[:status].to_s.presence_in(MEMBER_STATUS_FILTERS) || "active"
  end

  def load_students_for_roster
    @member_status ||= member_status_filter
    base_scope = @classroom.students
    @roster_students =
      if @member_status == "all"
        base_scope.order(active: :desc).in_roster_order
      else
        base_scope.where(active: @member_status == "active").in_roster_order
      end
  end

  def student_pin_error_message(pin)
    return t("students.members.pin_reset.blank") if pin.blank?
    return t("students.members.pin_reset.invalid") unless pin.match?(/\A\d{4}\z/)

    nil
  end

  def render_student_pin_error
    respond_to do |format|
      format.html do
        flash.now[:alert] = @student_pin_error
        render :edit_student_pin, status: :unprocessable_content
      end
      format.turbo_stream do
        flash.now[:alert] = @student_pin_error
        render :edit_student_pin, formats: :html, layout: false, status: :unprocessable_content
      end
    end
  end

  def render_student_roster_errors(error_key)
    respond_to do |format|
      format.html do
        flash.now[:alert] = t("students.members.update_names.#{error_key}")
        render :edit_student_names, status: :unprocessable_content, layout: false
      end
      format.turbo_stream do
        flash.now[:alert] = t("students.members.update_names.#{error_key}")
        render :edit_student_names, formats: :html, status: :unprocessable_content, layout: false
      end
    end
  end

  def members_redirect_path
    return classroom_members_path(@classroom, status: member_status_filter) if params.key?(:status)

    classroom_members_path(@classroom)
  end

end
