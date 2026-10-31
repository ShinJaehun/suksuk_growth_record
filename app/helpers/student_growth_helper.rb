module StudentGrowthHelper
  OVERALL_GROWTH_COLOR = "#475569".freeze

  def student_growth_color(virtue = nil)
    virtue ? virtue.color_hex : OVERALL_GROWTH_COLOR
  end

  def student_growth_chart(weekly_data, overall:, classroom: nil, student: nil)
    maximum = overall ? 100 : 5
    points = weekly_data.each_with_index.map do |day, index|
      value = day[:value]
      day.merge(
        x: 50 + index * 100,
        y: growth_chart_y(value, maximum),
        href: growth_date_selection_path(day[:date], classroom: classroom, student: student),
        selected: classroom.present? && day[:date] == @recorded_on,
        weekday: t("student_growth.weekdays")[day[:date].wday],
        label: value.nil? ? t("student_growth.no_data") : student_growth_value_label(value, overall:)
      )
    end

    { points: points, ticks: growth_chart_ticks(maximum, overall:), paths: student_growth_paths(points) }
  end

  def student_growth_metric_link(
    metric,
    label,
    href:,
    current_metric:,
    color: OVERALL_GROWTH_COLOR,
    data_key: :metric
  )
    swatch = tag.span class: "h-3 w-3 shrink-0 rounded-full ring-1 ring-white",
      style: "background-color: #{color}", aria: { hidden: true }, data: { metric_swatch: true }
    link_to safe_join([swatch, label]), href,
      class: class_names(
        "inline-flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm font-bold transition",
        "bg-blue-600 text-white" => current_metric == metric,
        "bg-slate-100 text-slate-600 hover:bg-slate-200" => current_metric != metric
      ),
      aria: { current: current_metric == metric ? "true" : nil },
      data: { data_key => metric }
  end

  def growth_dashboard_path(classroom: nil, student: nil, **query)
    query = { tab: "growth" }.merge(query)

    if classroom && student
      classroom_student_path(classroom, student, query)
    else
      student_growth_path(query)
    end
  end

  def daily_growth_status(record, recorded_on)
    if record
      t("teacher_growth_records.completed")
    elsif recorded_on == Time.zone.today
      t("teacher_growth_records.not_completed")
    else
      t("student_growth.no_data")
    end
  end

  def growth_visualization_params(classroom: nil)
    query = { tab: @tab.to_s, metric: @metric }
    if @tab == :monthly
      query[:month] = @calendar_month_param
    else
      query[:week_offset] = @week_offset
    end
    query[:date] = @recorded_on.iso8601 if classroom
    query
  end

  def growth_record_path(date, classroom: nil, student: nil)
    query = classroom ? growth_visualization_params(classroom: classroom) : {}
    growth_dashboard_path(classroom: classroom, student: student, **query, date: date.iso8601)
  end

  def growth_date_selection_path(date, classroom: nil, student: nil)
    return if date > Time.zone.today || date.saturday? || date.sunday? || @holidays_unavailable
    return if @public_holidays_by_date.fetch(date, []).any?
    return unless @records_by_date[date] || (classroom && date < Time.zone.today)

    growth_record_path(date, classroom: classroom, student: student)
  end

  def growth_calendar_weekday_classes(index)
    class_names("growth-calendar__weekday",
      "growth-calendar__weekday--sunday" => index.zero?,
      "growth-calendar__weekday--saturday" => index == 6)
  end

  def growth_calendar_day(date, classroom: nil, student: nil)
    in_month = date.between?(@calendar_month, @calendar_month.end_of_month)
    future = date > @today
    record = @records_by_date[date] if in_month && !future
    value = @monthly_values[date] if record
    state = if !in_month
      "outside_month"
    elsif future
      "future"
    elsif record.nil?
      "no_record"
    elsif value.nil?
      "no_score"
    else
      "scored"
    end
    holidays = in_month ? @public_holidays_by_date.fetch(date, []) : []
    status = if value
      t("student_growth.score", value: number_with_precision(value, precision: 1, strip_insignificant_zeros: true))
    elsif in_month && state != "no_record"
      t("student_growth.monthly.#{state}")
    end
    labels = [l(date, format: :growth_week), status]
    labels << t("student_growth.monthly.today") if date == @today
    labels.concat(holidays.map { |holiday| holiday.fetch(:name) })
    href = growth_date_selection_path(date, classroom: classroom, student: student) if in_month
    selected = classroom.present? && date == @recorded_on

    {
      date: date, value: value, radius: value && growth_calendar_bubble_radius(value),
      holidays: holidays,
      tag: href ? :a : :div,
      attributes: {
        href: href,
        class: class_names("growth-calendar__day",
          "growth-calendar__day--scored" => value.present?,
          "growth-calendar__day--selected" => selected,
          "growth-calendar__day--saturday" => date.saturday?,
          "growth-calendar__day--sunday" => date.sunday?,
          "growth-calendar__day--muted" => !in_month,
          "growth-calendar__day--today" => date == @today,
          "growth-calendar__day--public-holiday" => holidays.any?,
          "growth-calendar__day--future" => in_month && future),
        aria: { label: labels.compact.join(", "), current: selected ? "date" : nil },
        data: { calendar_date: date.iso8601, growth_value: value, calendar_state: state }
      }
    }
  end

  def growth_calendar_bubble_radius(value)
    # A shared 1..5 scale: small scores remain visible and 5 fits inside the cell.
    (9 + value.clamp(1, 5) * 6).round(2)
  end

  private

  def growth_chart_y(value, maximum)
    value.nil? ? nil : 180 - (value.fdiv(maximum) * 160).round
  end

  def growth_chart_ticks(maximum, overall:)
    (0..5).map do |step|
      value = maximum * step / 5
      { value: value, y: 180 - step * 32, label: student_growth_value_label(value, overall:) }
    end
  end

  def student_growth_value_label(value, overall:)
    if overall
      number_to_percentage(value, precision: 1, strip_insignificant_zeros: true)
    else
      t("student_growth.score", value: value)
    end
  end

  def student_growth_paths(points)
    # A missing day breaks the line; isolated scores still have a point marker.
    points.slice_when { |left, right| left[:value].nil? || right[:value].nil? }
      .filter_map do |segment|
        next if segment.size < 2 || segment.first[:value].nil?

        first_point = segment.first
        curve_segments = segment.each_cons(2).map do |start_point, end_point|
          midpoint_x = (start_point[:x] + end_point[:x]) / 2
          "C #{midpoint_x} #{start_point[:y]}, #{midpoint_x} #{end_point[:y]}, #{end_point[:x]} #{end_point[:y]}"
        end
        ["M #{first_point[:x]} #{first_point[:y]}", *curve_segments].join(" ")
      end
  end

end
