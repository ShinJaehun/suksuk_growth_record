module StudentGrowthHelper
  OVERALL_GROWTH_COLOR = "#475569".freeze

  def student_growth_color(virtue = nil)
    virtue ? virtue.color_hex : OVERALL_GROWTH_COLOR
  end

  def student_growth_chart(weekly_data, overall:)
    maximum = overall ? 100 : 5
    points = weekly_data.each_with_index.map do |day, index|
      value = day[:value]
      day.merge(
        x: 50 + index * 100,
        y: growth_chart_y(value, maximum),
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

  private

  def growth_chart_y(value, maximum)
    value.nil? ? nil : 150 - (value.fdiv(maximum) * 120).round
  end

  def growth_chart_ticks(maximum, overall:)
    (0..5).map do |step|
      value = maximum * step / 5
      { value: value, y: 150 - step * 24, label: student_growth_value_label(value, overall:) }
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
