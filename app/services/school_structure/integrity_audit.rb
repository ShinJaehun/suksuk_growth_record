module SchoolStructure
  class IntegrityAudit
    DEFAULT_SAMPLE_LIMIT = 20
    MAX_SAMPLE_LIMIT = 1_000

    ISSUE_LABELS = {
      teacher_without_school: 'teacher without school',
      teacher_classroom_school_mismatch: 'teacher/classroom school mismatch',
      teacher_classroom_grade_mismatch: 'teacher/classroom grade mismatch',
      inactive_teacher_assignment: 'inactive teacher assignment',
      invalid_homeroom_assignment_teacher_role: 'invalid homeroom assignment teacher role',
      duplicate_current_classroom_assignment: 'duplicate current classroom assignment',
      duplicate_current_teacher_assignment: 'duplicate current teacher assignment'
    }.freeze

    Issue = Data.define(:count, :samples)
    Result = Data.define(:issues) do
      def clean?
        issue_count.zero?
      end

      alias_method :success?, :clean?

      def issue_count
        issues.values.sum(&:count)
      end

      def count_for(type)
        issues.fetch(type).count
      end

      def samples_for(type)
        issues.fetch(type).samples
      end
    end

    def self.call(sample_limit: DEFAULT_SAMPLE_LIMIT)
      new(sample_limit: sample_limit).call
    end

    def initialize(sample_limit:)
      @sample_limit = sample_limit.to_i.clamp(0, MAX_SAMPLE_LIMIT)
    end

    def call
      Result.new(
        issues: {
          teacher_without_school: issue(
            teacher_without_school_scope,
            sample_scope: classroom_assignment_sample_scope(teacher_without_school_scope)
          ),
          teacher_classroom_school_mismatch: issue(
            teacher_school_mismatch_scope,
            sample_scope: classroom_assignment_sample_scope(teacher_school_mismatch_scope)
          ),
          teacher_classroom_grade_mismatch: issue(
            teacher_grade_mismatch_scope,
            sample_scope: classroom_assignment_sample_scope(teacher_grade_mismatch_scope)
          ),
          inactive_teacher_assignment: issue(
            inactive_teacher_assignment_scope,
            sample_scope: classroom_assignment_sample_scope(inactive_teacher_assignment_scope)
          ),
          invalid_homeroom_assignment_teacher_role: issue(
            invalid_assignment_teacher_role_scope,
            sample_scope: assignment_identity_sample_scope(invalid_assignment_teacher_role_scope)
          ),
          duplicate_current_classroom_assignment: issue(
            duplicate_current_classroom_assignment_scope,
            sample_scope: assignment_identity_sample_scope(duplicate_current_classroom_assignment_scope)
          ),
          duplicate_current_teacher_assignment: issue(
            duplicate_current_teacher_assignment_scope,
            sample_scope: assignment_identity_sample_scope(duplicate_current_teacher_assignment_scope)
          )
        }
      )
    end

    private

    attr_reader :sample_limit

    def classroom_assignment_sample_scope(scope)
      scope.select(
        'homeroom_assignments.id AS homeroom_assignment_id',
        'homeroom_assignments.classroom_id AS classroom_id',
        'homeroom_assignments.teacher_id AS user_id',
        'classrooms.school_year_id AS classroom_school_year_id',
        'users.school_year_id AS teacher_school_year_id',
        'users.grade AS teacher_grade',
        'classrooms.grade AS classroom_grade'
      )
    end

    def assignment_identity_sample_scope(scope)
      scope.select(:id, :classroom_id, :teacher_id, :started_on, :ended_on)
    end

    def teacher_without_school_scope
      current_assignment_scope
        .left_joins(teacher: :school_year)
        .where(school_years: { id: nil })
    end

    def teacher_school_mismatch_scope
      current_assignment_scope
        .where('users.school_year_id <> classrooms.school_year_id')
    end

    def teacher_grade_mismatch_scope
      current_assignment_scope
        .where('users.grade IS NULL OR users.grade <> classrooms.grade')
    end

    def inactive_teacher_assignment_scope
      current_assignment_scope
        .joins(classroom: :school_year)
        .where(users: { active: false })
        .where(school_years: { status: %w[planning active] })
    end

    def current_assignment_scope
      HomeroomAssignment.current.joins(:teacher, :classroom)
    end

    def invalid_assignment_teacher_role_scope
      HomeroomAssignment.joins(:teacher).where.not(users: { role: 'teacher' })
    end

    def duplicate_current_classroom_assignment_scope
      HomeroomAssignment.current
                        .where(classroom_id: HomeroomAssignment.current.group(:classroom_id).having('COUNT(*) > 1').select(:classroom_id))
    end

    def duplicate_current_teacher_assignment_scope
      HomeroomAssignment.current
                        .where(teacher_id: HomeroomAssignment.current.group(:teacher_id).having('COUNT(*) > 1').select(:teacher_id))
    end

    def issue(scope, sample_scope:)
      Issue.new(
        count: scope.except(:select, :order).count,
        samples: sample_attributes(sample_scope)
      )
    end

    def sample_attributes(scope)
      scope.order(Arel.sql('1')).limit(sample_limit).map do |record|
        record.attributes.except('id')
      end
    end
  end
end
