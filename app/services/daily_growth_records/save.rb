module DailyGrowthRecords
  class Save
    def self.call(student:, scores:, reflection: nil, record: nil)
      new(student:, scores:, reflection:, record:).call
    end

    def initialize(student:, scores:, reflection:, record:)
      @student = student
      @scores = scores.to_h.transform_keys(&:to_i)
      @reflection = reflection
      @record = record
    end

    def call
      DailyGrowthRecord.transaction do
        @record ? update_record : create_record
      end
    end

    private

    def create_record
      @student.classroom.with_lock do
        today = Time.zone.today
        configuration = @student.classroom.daily_virtue_configurations.includes(items: :virtue)
          .find_by(recorded_on: today) || capture_configuration(today)
        record = @student.daily_growth_records.build(
          classroom: @student.classroom,
          recorded_on: today,
          daily_virtue_configuration: configuration,
          reflection: @reflection
        )
        require_exact_scores!(record, configuration.items.map(&:virtue_id))
        configuration.items.each do |item|
          record.daily_growth_scores.build(virtue: item.virtue, score: @scores.fetch(item.virtue_id))
        end
        record.save!
        record
      end
    end

    def capture_configuration(today)
      configuration = @student.classroom.daily_virtue_configurations.build(recorded_on: today)
      @student.classroom.virtues.active.in_display_order.each do |virtue|
        configuration.items.build(virtue: virtue, name: virtue.name, position: virtue.position)
      end
      configuration.save!
      configuration
    end

    def update_record
      @record.with_lock do
        require_editable_record!
        existing_scores = @record.daily_growth_scores.includes(:virtue).to_a
        require_exact_scores!(@record, existing_scores.map(&:virtue_id))
        existing_scores.each { |growth_score| growth_score.score = @scores.fetch(growth_score.virtue_id) }
        @record.reflection = @reflection
        @record.save!
        existing_scores.each(&:save!)
        @record
      end
    end

    def require_editable_record!
      return if @record.student_id == @student.id && @record.recorded_on == Time.zone.today

      @record.errors.add(:base, :not_editable)
      raise ActiveRecord::RecordInvalid, @record
    end

    def require_exact_scores!(record, virtue_ids)
      return if @scores.keys.sort == virtue_ids.sort

      record.errors.add(:daily_growth_scores, :incomplete)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
