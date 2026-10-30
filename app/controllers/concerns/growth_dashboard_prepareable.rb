module GrowthDashboardPrepareable
  private

  def growth_dashboard_tab
    %w[weekly monthly].include?(params[:tab]) ? params[:tab].to_sym : :growth
  end

  def growth_dashboard_date
    value = params[:date]
    return Time.zone.today unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    date = Date.iso8601(value)
    [date, Time.zone.today].min
  rescue ArgumentError
    Time.zone.today
  end

  def prepare_growth_daily(student, classroom: nil)
    @recorded_on = growth_dashboard_date
    records = student.daily_growth_records
    records = records.where(classroom:) if classroom

    prepare_growth_history(records)
    @record = if @growth_records_range&.cover?(@recorded_on)
      @records_by_date[@recorded_on]
    else
      records.includes(:daily_growth_scores, daily_virtue_configuration: { items: :virtue })
        .find_by(recorded_on: @recorded_on)
    end
    @score_rows = growth_score_rows(@record)
  end

  def prepare_growth_history(records)
    records = records.where(recorded_on: ..Time.zone.today)
    @previous_record_date = records.where("recorded_on < ?", @recorded_on).maximum(:recorded_on)
    @next_record_date = records.where("recorded_on > ?", @recorded_on).minimum(:recorded_on)
  end

  def prepare_growth_form(student, submitted_scores: nil, reflection: nil)
    configuration = @record&.daily_virtue_configuration ||
      student.classroom.daily_virtue_configurations
        .includes(:items)
        .find_by(recorded_on: Time.zone.today)

    @virtue_fields = if configuration
      configuration.items.map { |item| { id: item.virtue_id, name: item.name } }
    else
      student.classroom.virtues.active.in_display_order.map do |virtue|
        { id: virtue.id, name: virtue.name }
      end
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

  def prepare_growth_week(student, classroom: nil)
    requested_offset = Integer(params[:week_offset].to_s, exception: false) || 0
    @week_offset = [requested_offset, 0].min
    @week_start = Time.zone.today.beginning_of_week(:monday) + @week_offset.weeks
    @chart_end = @week_start + 4.days
    @records_by_date = growth_records_for(student, @week_start..@chart_end, classroom: classroom)
    prepare_growth_metrics(student)
    @weekly_data = (@week_start..@chart_end).map do |date|
      { date: date, value: growth_metric_value(@records_by_date[date], @selected_virtue) }
    end
    prepare_growth_holidays(@week_start..@chart_end)
  end

  def prepare_growth_month(student, classroom: nil)
    @today = Time.zone.today
    @calendar_month = growth_dashboard_month
    @calendar_month_param = @calendar_month.strftime("%Y-%m")
    @previous_calendar_month_param = @calendar_month.prev_month.strftime("%Y-%m")
    @next_calendar_month_param = @calendar_month.next_month.strftime("%Y-%m")
    @calendar_starts_on = @calendar_month.beginning_of_week(:sunday)
    @calendar_ends_on = @calendar_month.end_of_month.end_of_week(:sunday)
    @calendar_weeks = (@calendar_starts_on..@calendar_ends_on).to_a.each_slice(7).to_a
    @records_by_date = growth_records_for(student, @calendar_month..[@calendar_month.end_of_month, @today].min, classroom: classroom)
    prepare_growth_metrics(student, retain_metric: true)
    @monthly_values = @records_by_date.transform_values do |record|
      growth_metric_value(record, @selected_virtue, overall_percentage: false)
    end
    prepare_growth_holidays(@calendar_month..@calendar_month.end_of_month)
  end

  def prepare_growth_holidays(range)
    holidays = (range.begin.year..range.end.year).map { |year| PublicHolidays::Calendar.for_year(year) }
    @holidays_unavailable = holidays.any?(&:nil?)
    @public_holidays_by_date = holidays.compact.flatten.group_by { |holiday| holiday.fetch(:date) }
  end

  def growth_dashboard_month
    current_month = Time.zone.today.beginning_of_month
    value = params[:month]
    return current_month unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}\z/)

    [Date.strptime("#{value}-01", "%Y-%m-%d"), current_month].min
  rescue ArgumentError
    current_month
  end

  def prepare_growth_metrics(student, retain_metric: false)
    @virtues = available_growth_virtues(student, @records_by_date.values)
    @selected_virtue = @virtues.find { |virtue| virtue.id.to_s == params[:metric].to_s }
    # Keep an already scored inactive metric selected when moving to an empty month.
    if retain_metric && @selected_virtue.nil? && params[:metric].present?
      @selected_virtue = student.classroom.virtues
        .joins(daily_growth_scores: :daily_growth_record)
        .where(daily_growth_records: { student_id: student.id, recorded_on: ..Time.zone.today })
        .find_by(id: params[:metric].to_s)
      @virtues = (@virtues + [@selected_virtue]).sort_by { |virtue| [virtue.position, virtue.id] } if @selected_virtue
    end
    @metric = @selected_virtue ? @selected_virtue.id.to_s : "overall"
  end

  def growth_records_for(student, range, classroom: nil)
    @growth_records_range = range
    records = student.daily_growth_records.where(recorded_on: range).includes(:daily_growth_scores)
    if classroom
      records = records.where(classroom: classroom)
        .includes(daily_virtue_configuration: { items: :virtue })
    end
    records.index_by(&:recorded_on)
  end

  def available_growth_virtues(student, records)
    scored_virtue_ids = records.flat_map do |record|
      record.daily_growth_scores.map(&:virtue_id)
    end
    classroom_virtues = student.classroom.virtues
    classroom_virtues.active
      .or(classroom_virtues.where(id: scored_virtue_ids))
      .in_display_order.to_a
  end

  def growth_metric_value(record, selected_virtue, overall_percentage: true)
    return unless record

    if selected_virtue
      record.daily_growth_scores.find { |score| score.virtue_id == selected_virtue.id }&.score
    else
      average = record.average_score
      return average unless overall_percentage

      average / 5.0 * 100 if average
    end
  end

  def growth_score_rows(record)
    return [] unless record

    scores_by_virtue_id = record.daily_growth_scores.index_by(&:virtue_id)
    record.daily_virtue_configuration.items.filter_map do |item|
      score = scores_by_virtue_id[item.virtue_id]
      next unless score

      {
        virtue_id: item.virtue_id,
        name: item.name,
        value: score.score,
        color: item.virtue.color_hex,
        label: t("daily_growth_records.score_labels.#{score.score}")
      }
    end
  end
end
