class StudentGrowthController < ApplicationController
  before_action :require_student_session

  def show
    authorize current_student, :manage_own_growth_record?
    prepare_week
    load_records
    prepare_metric
    prepare_weekly_data
  end

  private

  def require_student_session
    return if current_student

    redirect_to new_student_session_path, alert: t("student_sessions.invalid")
  end

  def prepare_week
    requested_offset = Integer(params[:week_offset].to_s, exception: false) || 0
    @week_offset = [requested_offset, 0].min
    @week_start = Time.zone.today.beginning_of_week(:monday) + @week_offset.weeks
    @chart_end = @week_start + 4.days
  end

  def load_records
    @records_by_date = current_student.daily_growth_records
      .where(recorded_on: @week_start..@chart_end)
      .includes(:daily_growth_scores)
      .index_by(&:recorded_on)
  end

  def prepare_metric
    scored_virtue_ids = @records_by_date.values.flat_map do |record|
      record.daily_growth_scores.map(&:virtue_id)
    end
    classroom_virtues = current_student.classroom.virtues
    @virtues = classroom_virtues.active
      .or(classroom_virtues.where(id: scored_virtue_ids))
      .in_display_order.to_a
    @selected_virtue = @virtues.find { |virtue| virtue.id.to_s == params[:metric].to_s }
    @metric = @selected_virtue ? @selected_virtue.id.to_s : "overall"
  end

  def prepare_weekly_data
    @weekly_data = (@week_start..@chart_end).map do |date|
      { date: date, value: metric_value(@records_by_date[date]) }
    end
  end

  def metric_value(record)
    return unless record

    if @selected_virtue
      record.daily_growth_scores.find { |score| score.virtue_id == @selected_virtue.id }&.score
    else
      average = record.average_score
      average / 5.0 * 100 if average
    end
  end
end
