class StudentGrowthController < ApplicationController
  include GrowthDashboardPrepareable

  before_action :require_student_session

  def show
    authorize current_student, :manage_own_growth_record?
    @tab = growth_dashboard_tab

    if @tab == :weekly
      prepare_growth_week(current_student)
    elsif @tab == :growth
      prepare_growth_daily(current_student)
      @can_edit_record = @recorded_on == Time.zone.today
      @editing = @can_edit_record && (@record.nil? || params[:edit] == "1")
      prepare_growth_form(current_student) if @editing
    end
  end

  private

  def require_student_session
    return if current_student

    redirect_to new_student_session_path, alert: t("student_sessions.invalid")
  end
end
