class StudentGrowthRecordsController < ApplicationController
  include GrowthDashboardPrepareable

  before_action :require_student_session

  def show
    authorize current_student, :manage_own_growth_record?
    redirect_to student_growth_path(tab: "growth")
  end

  def create
    authorize current_student, :manage_own_growth_record?
    DailyGrowthRecords::Save.call(student: current_student, **growth_record_attributes)
    redirect_to student_growth_path(tab: "growth"),
      notice: t("daily_growth_records.notices.created"),
      status: :see_other
  rescue ActiveRecord::RecordInvalid
    @record = nil
    render_invalid_form
  end

  def update
    authorize current_student, :manage_own_growth_record?
    load_today_record!
    DailyGrowthRecords::Save.call(
      student: current_student,
      record: @record,
      **growth_record_attributes
    )
    redirect_to student_growth_path(tab: "growth"),
      notice: t("daily_growth_records.notices.updated"),
      status: :see_other
  rescue ActiveRecord::RecordInvalid
    render_invalid_form
  end

  private

  def require_student_session
    return if current_student

    redirect_to new_student_session_path, alert: t("student_sessions.invalid")
  end

  def load_today_record!
    @record = current_student.daily_growth_records
      .includes(:daily_growth_scores, daily_virtue_configuration: :items)
      .find_by!(recorded_on: Time.zone.today)
  end

  def render_invalid_form
    @tab = :growth
    @recorded_on = Time.zone.today
    prepare_growth_history(current_student.daily_growth_records)
    @editing = true
    prepare_growth_form(
      current_student,
      submitted_scores: submitted_scores,
      reflection: submitted_reflection
    )
    flash.now[:alert] = t("daily_growth_records.errors.invalid")
    render "student_growth/show", status: :unprocessable_content
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
