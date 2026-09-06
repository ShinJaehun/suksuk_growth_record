module ClassroomStudents
  class BulkRegistration
    Result = Struct.new(:students, :rows, :error, :row_errors, keyword_init: true) do
      def success? = error.blank?
    end

    def self.preview(classroom:, student_pin:, student_count:)
      new(classroom:, student_pin:, rows: {}).validate_setup(student_count)
    end

    def self.call(classroom:, student_pin:, rows:)
      new(classroom:, student_pin:, rows:).call
    end

    def initialize(classroom:, student_pin:, rows:)
      @classroom = classroom
      @student_pin = student_pin.to_s.strip
      @rows = normalize_rows(rows)
    end

    def validate_setup(student_count)
      error = setup_error(student_count)
      @rows = build_rows(student_count.to_i) unless error
      Result.new(students: [], rows: @rows, error:, row_errors: {})
    end

    def call
      error, row_errors = validate_rows
      return failure(error, row_errors) if error

      created = []
      current_row = nil
      @classroom.with_lock do
        return failure(limit_error, {}) if over_limit?(@rows.size)

        @rows.each do |row|
          current_row = row
          created << @classroom.students.create!(
            name: row[:name],
            student_number: row[:student_number].presence,
            gender: row[:gender],
            avatar_key: row[:avatar_key],
            student_pin: @student_pin
          )
        end
      end
      Result.new(students: created, rows: @rows, error: nil, row_errors: {})
    rescue ActiveRecord::RecordInvalid => e
      message = t("students.bulk_create.failure", detail: e.record.errors.full_messages.to_sentence)
      failure(message, current_row ? { current_row[:index] => [message] } : {})
    rescue ActiveRecord::RecordNotUnique
      message = t("students.bulk_create.errors.student_number_taken", number: current_row&.dig(:student_number))
      failure(message, current_row ? { current_row[:index] => [message] } : {})
    end

    private

    def normalize_rows(rows)
      raw = rows.respond_to?(:to_unsafe_h) ? rows.to_unsafe_h : rows
      raw = raw.to_h if raw.respond_to?(:to_h)
      return [] unless raw.respond_to?(:each_with_index)

      raw.each_with_index.map do |(index, attrs), fallback|
        attrs = attrs.to_unsafe_h if attrs.respond_to?(:to_unsafe_h)
        attrs = attrs.to_h
        {
          index: index.presence || fallback.to_s,
          student_number: fetch(attrs, :student_number).to_s,
          name: fetch(attrs, :name).to_s,
          gender: fetch(attrs, :gender).to_s,
          avatar_key: fetch(attrs, :avatar_key).to_s
        }
      end
    end

    def fetch(attrs, key) = attrs.fetch(key.to_s) { attrs.fetch(key, "") }

    def build_rows(count)
      Array.new(count) do |index|
        {
          index: index.to_s,
          student_number: (index + 1).to_s,
          name: "",
          gender: "",
          avatar_key: ""
        }
      end
    end

    def setup_error(count)
      return t("students.bulk_create.errors.invalid_count") unless count.to_s.match?(/\A[1-9]\d*\z/)
      return limit_error if over_limit?(count.to_i)
      return t("students.bulk_create.errors.invalid_pin") unless valid_pin?
    end

    def validate_rows
      errors = {}
      errors[:base] = t("students.bulk_create.errors.empty") if @rows.empty?
      errors[:base] = limit_error if over_limit?(@rows.size)
      errors[:base] = t("students.bulk_create.errors.invalid_pin") unless valid_pin?
      numbered = @rows.select { |row| valid_number?(row[:student_number]) && row[:student_number].present? }
      duplicates = numbered.group_by { |row| row[:student_number].to_i }.select { |_number, values| values.many? }.keys
      existing = @classroom.students.active.where(student_number: numbered.map { |row| row[:student_number].to_i }).pluck(:student_number)

      @rows.each do |row|
        row_errors = []
        number = row[:student_number]
        row_errors << t("students.create.errors.student_number_invalid") unless valid_number?(number)
        row_errors << t("students.bulk_create.errors.student_number_duplicate_in_draft", number:) if number.present? && duplicates.include?(number.to_i)
        row_errors << t("students.bulk_create.errors.student_number_taken", number:) if number.present? && existing.include?(number.to_i)
        row_errors << t("students.bulk_create.errors.name_required") if row[:name].blank?
        row_errors << t("students.bulk_create.errors.gender_required") unless Student::GENDERS.include?(row[:gender])
        if row[:avatar_key].blank?
          row_errors << t("students.bulk_create.errors.avatar_required")
        elsif !avatar_matches_gender?(row[:gender], row[:avatar_key])
          row_errors << t("students.bulk_create.errors.invalid_avatar")
        end
        errors[row[:index]] = row_errors if row_errors.any?
      end
      [errors[:base] || errors.values.flatten.first, errors.except(:base)]
    end

    def valid_number?(number) = number.blank? || number.match?(/\A[1-9]\d*\z/)
    def valid_pin? = @student_pin.match?(/\A\d{4}\z/)
    def avatar_matches_gender?(gender, avatar_key) = Student.avatar_keys_for(gender).include?(avatar_key)
    def over_limit?(count) = @classroom.active_students_count + count > Classroom::MAX_ACTIVE_STUDENTS
    def limit_error = t("students.bulk_create.errors.too_many", count: Classroom::MAX_ACTIVE_STUDENTS)
    def failure(error, row_errors) = Result.new(students: [], rows: @rows, error:, row_errors:)
    def t(key, **options) = I18n.t(key, **options)
  end
end
