class StudentGrowthRecordsController < ApplicationController
  before_action :require_student_session

  def show
    authorize current_student, :manage_own_growth_record?
    load_today_record
    prepare_form
  end

  def create
    authorize current_student, :manage_own_growth_record?
    DailyGrowthRecords::Save.call(student: current_student, **growth_record_attributes)
    redirect_to student_growth_record_path,
      notice: t("daily_growth_records.notices.created"),
      status: :see_other
  rescue ActiveRecord::RecordInvalid
    @record = nil
    prepare_form(submitted_scores: submitted_scores, reflection: submitted_reflection)
    flash.now[:alert] = t("daily_growth_records.errors.invalid")
    render :show, status: :unprocessable_content
  end

  def update
    authorize current_student, :manage_own_growth_record?
    load_today_record!
    DailyGrowthRecords::Save.call(
      student: current_student,
      record: @record,
      **growth_record_attributes
    )
    redirect_to student_growth_record_path,
      notice: t("daily_growth_records.notices.updated"),
      status: :see_other
  rescue ActiveRecord::RecordInvalid
    prepare_form(submitted_scores: submitted_scores, reflection: submitted_reflection)
    flash.now[:alert] = t("daily_growth_records.errors.invalid")
    render :show, status: :unprocessable_content
  end

  private

  def require_student_session
    return if current_student

    redirect_to new_student_session_path, alert: t("student_sessions.invalid")
  end

  def load_today_record
    @record = current_student.daily_growth_records
      .includes(:daily_growth_scores, daily_virtue_configuration: :items)
      .find_by(recorded_on: Time.zone.today)
  end

  def load_today_record!
    @record = current_student.daily_growth_records
      .includes(:daily_growth_scores, daily_virtue_configuration: :items)
      .find_by!(recorded_on: Time.zone.today)
  end

  def prepare_form(submitted_scores: nil, reflection: nil)
    configuration = @record&.daily_virtue_configuration ||
      current_student.classroom.daily_virtue_configurations.includes(:items).find_by(recorded_on: Time.zone.today)
    @virtue_fields = if configuration
      configuration.items.map { |item| { id: item.virtue_id, name: item.name } }
    else
      current_student.classroom.virtues.active.in_display_order.map { |virtue| { id: virtue.id, name: virtue.name } }
    end

    if @record
      stored_scores = @record.daily_growth_scores.index_by(&:virtue_id).transform_values(&:score)
      @selected_scores = submitted_scores || stored_scores.transform_keys(&:to_s)
      @reflection = reflection.nil? ? @record.reflection : reflection
    else
      @selected_scores = submitted_scores || {}
      @reflection = reflection
    end
  end

  def growth_record_attributes
    { scores: submitted_scores, reflection: submitted_reflection }
  end

  def submitted_scores
    growth_record_params.fetch(:scores, {}).to_h
  end

  def submitted_reflection
    growth_record_params[:reflection]
  end

  def growth_record_params
    @growth_record_params ||= params.require(:daily_growth_record).permit(:reflection, scores: {})
  end
end
