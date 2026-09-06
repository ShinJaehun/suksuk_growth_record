module Teachers
  class SaveWithAssignment
    UNCHANGED_MEMBERSHIP_GRADE = Object.new.freeze

    Result = Data.define(:teacher, :error_messages, :temporary_password) do
      def success?
        error_messages.empty?
      end
    end

    def self.call(teacher:, attributes:, school:, classroom_id:, actor:, membership_grade: UNCHANGED_MEMBERSHIP_GRADE)
      new(
        teacher: teacher,
        attributes: attributes,
        school: school,
        classroom_id: classroom_id,
        membership_grade: membership_grade,
        actor: actor
      ).call
    end

    def initialize(teacher:, attributes:, school:, classroom_id:, membership_grade:, actor:)
      @teacher = teacher
      @attributes = attributes
      @school = school
      @raw_classroom_id = classroom_id
      @membership_grade = membership_grade
      @actor = actor
    end

    def call
      User.transaction do
        teacher.lock! if teacher.persisted?
        @current_classroom = teacher.assigned_classroom
        validate_annual_school_immutability
        raise ActiveRecord::Rollback if teacher.errors.any?

        teacher.assign_attributes(attributes)
        normalize_inputs
        validate_inactive_assignment_lock
        validate_inputs
        raise ActiveRecord::Rollback if teacher.errors.any?

        [current_classroom, classroom].compact.uniq.sort_by(&:id).each(&:lock!)

        persist_teacher!
        current_classroom.update!(teacher: nil) if current_classroom && current_classroom != classroom
        classroom.update!(teacher: teacher) if classroom && classroom.teacher_id != teacher.id
      end

      result
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      @temporary_password = nil
      copy_persistence_errors(error)
      result
    end

    private

    attr_reader :teacher, :attributes, :school, :raw_classroom_id, :membership_grade, :classroom, :grade,
                :current_classroom, :actor, :temporary_password

    def normalize_inputs
      normalize_login_id
      @grade = normalized_grade
      @classroom = normalized_classroom
    end

    def normalize_login_id
      return unless teacher.new_record? || teacher.will_save_change_to_login_id?

      teacher.login_id = teacher.login_id.to_s.strip.downcase
    end

    def validate_inputs
      add_error(:teacher_required) unless teacher.teacher?
      add_error(:school_not_found) unless school.is_a?(School)
      add_error(:school_not_found) if school && target_school_year.nil?
      add_error(:login_id_required) if teacher.login_id.blank?
      add_error(:membership_grade_invalid) if invalid_grade?
      add_error(:classroom_not_found) if invalid_classroom_id?
      if school&.inactive? && (teacher.annual_school != school || classroom)
        add_inactive_school_error
      end
      return if teacher.errors.any? || classroom.nil?

      add_error(:school_required_for_classrooms) unless school
      add_error(:classroom_school_mismatch) unless classroom.school_year_id == target_school_year&.id
      add_error(:classroom_grade_mismatch) unless grade && classroom.grade == grade
      add_error(:inactive_teacher) unless teacher.active?
      add_error(:inactive_classroom) unless classroom.active? || classroom == current_classroom
      add_error(:classroom_already_assigned) if classroom.teacher_id.present? && classroom.teacher_id != teacher.id
    end

    def validate_annual_school_immutability
      return unless teacher.persisted?
      return if teacher.annual_school == school

      add_error(:annual_school_immutable)
    end

    def validate_inactive_assignment_lock
      return unless current_classroom&.inactive?
      return if school == teacher.annual_school &&
                grade == teacher.grade &&
                classroom == current_classroom

      add_error(:inactive_classroom_assignment_locked)
    end

    def normalized_grade
      return teacher.grade if membership_grade.equal?(UNCHANGED_MEMBERSHIP_GRADE)
      return nil if membership_grade.blank?

      membership_grade.to_i if membership_grade.to_s.match?(/\A[1-6]\z/)
    end

    def invalid_grade?
      !membership_grade.equal?(UNCHANGED_MEMBERSHIP_GRADE) && membership_grade.present? && grade.nil?
    end

    def normalized_classroom
      return nil if raw_classroom_id.blank?
      return nil unless raw_classroom_id.to_s.match?(/\A[1-9]\d*\z/)

      Classroom.find_by(id: raw_classroom_id)
    end

    def invalid_classroom_id?
      raw_classroom_id.present? && classroom.nil?
    end

    def persist_teacher!
      teacher.assign_attributes(grade: grade)
      if teacher.new_record?
        teacher.assign_attributes(
          school_year: target_school_year,
          login_id: teacher.login_id.to_s.strip.downcase,
          school_role: "member"
        )
        credential = AnnualTeacherUsers::TemporaryCredential.call(
          teacher: teacher,
          actor: actor,
          action: :temporary_password_issued
        )
        raise ActiveRecord::Rollback unless credential.success?

        @temporary_password = credential.temporary_password
      else
        teacher.save!
      end
    end

    def target_school_year
      return @target_school_year if defined?(@target_school_year)

      active_school_years = school&.school_years&.active&.limit(2)&.to_a || []
      @target_school_year = active_school_years.one? ? active_school_years.first : nil
    end

    def add_error(key)
      teacher.errors.add(:base, I18n.t("admin.teachers.errors.#{key}"))
    end

    def add_inactive_school_error
      teacher.errors.add(:base, I18n.t("school_status.inactive_school"))
    end

    def copy_persistence_errors(error)
      record = error.respond_to?(:record) ? error.record : nil
      if record&.errors&.any? && record != teacher
        record.errors.full_messages.each { |message| teacher.errors.add(:base, message) }
      elsif record != teacher
        add_error(:assignment_save_failed)
      end
    end

    def result
      Result.new(
        teacher: teacher,
        error_messages: teacher.errors.full_messages,
        temporary_password: temporary_password
      )
    end
  end
end
