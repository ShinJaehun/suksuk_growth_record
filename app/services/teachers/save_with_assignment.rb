module Teachers
  class SaveWithAssignment
    UNCHANGED_MEMBERSHIP_GRADE = Object.new.freeze

    Result = Data.define(:teacher, :error_messages) do
      def success?
        error_messages.empty?
      end
    end

    def self.call(teacher:, attributes:, school:, classroom_id:, membership_grade: UNCHANGED_MEMBERSHIP_GRADE)
      new(
        teacher: teacher,
        attributes: attributes,
        school: school,
        classroom_id: classroom_id,
        membership_grade: membership_grade
      ).call
    end

    def initialize(teacher:, attributes:, school:, classroom_id:, membership_grade:)
      @teacher = teacher
      @attributes = attributes
      @school = school
      @raw_classroom_id = classroom_id
      @membership_grade = membership_grade
    end

    def call
      User.transaction do
        teacher.lock! if teacher.persisted?
        teacher.assign_attributes(attributes)
        normalize_inputs
        validate_inputs
        raise ActiveRecord::Rollback if teacher.errors.any?

        current_classroom = teacher.assigned_classroom
        [current_classroom, classroom].compact.uniq.sort_by(&:id).each(&:lock!)

        teacher.save!
        sync_school_membership!
        current_classroom.update!(teacher: nil) if current_classroom && current_classroom != classroom
        classroom.update!(teacher: teacher) if classroom && classroom.teacher_id != teacher.id
      end

      result
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      copy_persistence_errors(error)
      result
    end

    private

    attr_reader :teacher, :attributes, :school, :raw_classroom_id, :membership_grade, :classroom, :grade

    def normalize_inputs
      @grade = normalized_grade
      @classroom = normalized_classroom
    end

    def validate_inputs
      add_error(:teacher_required) unless teacher.teacher?
      add_error(:school_not_found) unless school.nil? || school.is_a?(School)
      add_error(:membership_grade_invalid) if invalid_grade?
      add_error(:classroom_not_found) if invalid_classroom_id?
      add_inactive_school_error if school&.inactive?
      return if teacher.errors.any? || classroom.nil?

      add_error(:school_required_for_classrooms) unless school
      add_error(:classroom_school_mismatch) if school && classroom.school_id != school.id
      add_error(:classroom_grade_mismatch) unless grade && classroom.grade == grade
      add_error(:inactive_teacher) unless teacher.active?
      add_error(:inactive_classroom) unless classroom.active?
      add_error(:classroom_already_assigned) if classroom.teacher_id.present? && classroom.teacher_id != teacher.id
    end

    def normalized_grade
      return teacher.school_membership&.grade if membership_grade.equal?(UNCHANGED_MEMBERSHIP_GRADE)
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

    def sync_school_membership!
      membership = teacher.school_membership
      if school.nil?
        membership&.destroy!
      elsif membership
        changes = { school: school }
        changes[:grade] = grade unless membership_grade.equal?(UNCHANGED_MEMBERSHIP_GRADE)
        changes[:role] = :member if membership.school_id != school.id
        membership.update!(changes)
      else
        teacher.create_school_membership!(school: school, grade: grade)
      end
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
      Result.new(teacher: teacher, error_messages: teacher.errors.full_messages)
    end
  end
end
