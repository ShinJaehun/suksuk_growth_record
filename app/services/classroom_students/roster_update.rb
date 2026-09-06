module ClassroomStudents
  class RosterUpdate
    Result = Struct.new(:students, :rows, :row_errors, :error_key, keyword_init: true) do
      def success? = error_key.nil?
    end

    def self.call(classroom:, students:, rows:)
      new(classroom:, students:, rows:).call
    end

    def initialize(classroom:, students:, rows:)
      @classroom = classroom
      @editable_students = students
      @rows = normalize_rows(rows)
      @row_errors = Hash.new { |hash, key| hash[key] = [] }
    end

    def call
      saved = false
      @classroom.with_lock do
        @students = @editable_students.to_a
        editable_by_id = @students.index_by { |student| student.id.to_s }
        return failure(:invalid_membership) if (@rows.keys - editable_by_id.keys).any?

        selected = editable_by_id.slice(*@rows.keys)
        assign_and_validate(selected)
        next if @row_errors.any?

        changed = selected.values.select { |student| student.active? && student.will_save_change_to_student_number? }
        Student.where(id: changed.map(&:id)).update_all(student_number: nil) if changed.any?
        selected.each_value { |student| student.save! if student.has_changes_to_save? }
        saved = true
      end
      saved ? success : failure(:failure)
    rescue ActiveRecord::RecordInvalid => e
      attach_record_error(e.record)
      failure(:failure)
    rescue ActiveRecord::RecordNotUnique
      attach_record_not_unique_errors
      failure(:failure)
    end

    private

    def normalize_rows(rows)
      raw_rows = rows.respond_to?(:to_unsafe_h) ? rows.to_unsafe_h : rows
      raw_rows = raw_rows.to_h if raw_rows.respond_to?(:to_h)
      raw_rows = {} unless raw_rows.respond_to?(:each_with_object)

      raw_rows.each_with_object({}) do |(student_id, attributes), result|
        attributes = attributes.to_unsafe_h if attributes.respond_to?(:to_unsafe_h)
        attributes = attributes.to_h if attributes.respond_to?(:to_h)
        attributes = {} unless attributes.respond_to?(:key?)

        result[student_id.to_s] = %w[student_number name gender avatar_key].each_with_object({}) do |key, permitted|
          if attributes.key?(key)
            permitted[key] = attributes[key].to_s
          elsif attributes.key?(key.to_sym)
            permitted[key] = attributes[key.to_sym].to_s
          end
        end
      end
    end

    def assign_and_validate(selected)
      selected.each do |student_id, student|
        attributes = @rows.fetch(student_id)
        assign_student_number(student_id, student, attributes)
        assign_student_profile(student_id, student, attributes)
      end

      validate_final_active_student_numbers(selected)

      selected.each do |student_id, student|
        student.valid?
        student.errors.each do |error|
          next if error.attribute == :student_number && error.type == :taken

          @row_errors[student_id] << error.full_message
        end
      end
      @row_errors.delete_if { |_student_id, errors| errors.empty? }
    end

    def assign_student_number(student_id, student, attributes)
      raw_number = attributes.fetch('student_number', student.student_number_before_type_cast.to_s)
      attributes['student_number'] = raw_number
      if raw_number.present? && !raw_number.match?(/\A[1-9]\d*\z/)
        @row_errors[student_id] << t('students.members.update_names.invalid_student_number')
        return
      end

      student.student_number = raw_number.presence
    end

    def assign_student_profile(student_id, student, attributes)
      original_gender = student.gender
      original_avatar_key = student.avatar_key
      student.name = attributes.fetch('name', student.name)

      if attributes.key?('gender')
        gender = attributes['gender']
        unless Student::GENDERS.include?(gender)
          @row_errors[student_id] << t('students.members.update_names.invalid_gender')
          return
        end
        student.gender = gender
      end

      submitted_avatar_key = attributes.fetch('avatar_key', student.avatar_key.to_s)
      attributes['avatar_key'] = normalized_avatar_key(
        student,
        submitted_avatar_key,
        original_gender:,
        original_avatar_key:
      )

      if invalid_avatar_change?(student, attributes['avatar_key'], original_avatar_key)
        @row_errors[student_id] << t('students.members.update_names.invalid_avatar')
        return
      end

      student.avatar_key = attributes['avatar_key'].presence
    end

    def normalized_avatar_key(student, submitted_avatar_key, original_gender:, original_avatar_key:)
      pool = Student.avatar_keys_for(student.gender)
      gender_changed = student.gender != original_gender
      return submitted_avatar_key if !gender_changed && submitted_avatar_key == original_avatar_key
      return submitted_avatar_key if pool.include?(submitted_avatar_key)
      return submitted_avatar_key if student.gender.blank?
      return submitted_avatar_key unless submitted_avatar_key.blank? || submitted_avatar_key == original_avatar_key

      row_index = @students.index(student) || 0
      pool[row_index % pool.length]
    end

    def invalid_avatar_change?(student, avatar_key, original_avatar_key)
      return false if avatar_key.blank?
      return false if Student.avatar_keys_for(student.gender).include?(avatar_key)
      return false if avatar_key == original_avatar_key

      true
    end

    def validate_final_active_student_numbers(selected)
      submitted_numbers = selected.transform_values(&:student_number)
      final_numbers = @classroom.students.active.map do |student|
        [student, submitted_numbers.fetch(student.id.to_s, student.student_number)]
      end

      final_numbers
        .reject { |_student, number| number.nil? }
        .group_by { |_student, number| number }
        .each_value do |matching_rows|
          next unless matching_rows.many?

          matching_rows.each do |student, number|
            student_id = student.id.to_s
            next unless selected.key?(student_id)

            @row_errors[student_id] << t('students.members.update_names.duplicate_student_number', number:)
          end
        end
    end

    def attach_record_error(record)
      student = @students&.find { |candidate| candidate == record }
      return unless student

      @row_errors[student.id.to_s].concat(record.errors.full_messages)
    end

    def attach_record_not_unique_errors
      @rows.each do |student_id, attributes|
        next if attributes['student_number'].blank?

        student = @students&.find { |candidate| candidate.id.to_s == student_id }
        next unless student&.active?

        @row_errors[student_id] << t(
          'students.members.update_names.duplicate_student_number',
          number: attributes['student_number']
        )
      end
    end

    def success = Result.new(students: @students, rows: @rows, row_errors: @row_errors, error_key: nil)

    def failure(key)
      Result.new(students: @students || Array(@editable_students), rows: @rows, row_errors: @row_errors, error_key: key)
    end

    def t(key, **options) = I18n.t(key, **options)
  end
end
