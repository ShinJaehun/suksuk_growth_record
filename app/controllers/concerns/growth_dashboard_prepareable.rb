module GrowthDashboardPrepareable
  private

  def growth_dashboard_tab
    params[:tab] == "growth" ? :growth : :today
  end

  def prepare_growth_dashboard(student)
    prepare_growth_week(student)
  end

  def prepare_growth_today(student, classroom: nil)
    records = student.daily_growth_records
    records = records.where(classroom:) if classroom

    @record = records
      .includes(:daily_growth_scores, daily_virtue_configuration: { items: :virtue })
      .find_by(recorded_on: Time.zone.today)
    @score_rows = growth_score_rows(@record)
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

  def prepare_growth_week(student)
    requested_offset = Integer(params[:week_offset].to_s, exception: false) || 0
    @week_offset = [requested_offset, 0].min
    @week_start = Time.zone.today.beginning_of_week(:monday) + @week_offset.weeks
    @chart_end = @week_start + 4.days
    @records_by_date = growth_records_for(student, @week_start..@chart_end)
    @virtues = available_growth_virtues(student, @records_by_date.values)
    @selected_virtue = @virtues.find { |virtue| virtue.id.to_s == params[:metric].to_s }
    @metric = @selected_virtue ? @selected_virtue.id.to_s : "overall"
    @weekly_data = (@week_start..@chart_end).map do |date|
      { date: date, value: growth_metric_value(@records_by_date[date], @selected_virtue) }
    end
  end

  def growth_records_for(student, range)
    student.daily_growth_records
      .where(recorded_on: range)
      .includes(:daily_growth_scores)
      .index_by(&:recorded_on)
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

  def growth_metric_value(record, selected_virtue)
    return unless record

    if selected_virtue
      record.daily_growth_scores.find { |score| score.virtue_id == selected_virtue.id }&.score
    else
      average = record.average_score
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
