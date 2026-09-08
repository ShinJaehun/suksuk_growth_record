class StudentGrowthController < ApplicationController
  include GrowthDashboardPrepareable

  before_action :require_student_session

  def show
    authorize current_student, :manage_own_growth_record?
    @tab = growth_dashboard_tab

    if @tab == :growth
      prepare_growth_dashboard(current_student)
    else
      prepare_growth_today(current_student)
      @editing = @record.nil? || params[:edit] == "1"
      prepare_growth_form(current_student) if @editing
    end
  end

  private

  def require_student_session
    return if current_student

    redirect_to new_student_session_path, alert: t("student_sessions.invalid")
  end
end
