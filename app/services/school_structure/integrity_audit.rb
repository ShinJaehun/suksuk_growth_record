module SchoolStructure
  class IntegrityAudit
    DEFAULT_SAMPLE_LIMIT = 20
    MAX_SAMPLE_LIMIT = 1_000

    ISSUE_LABELS = {
      role_mismatch: 'role mismatch',
      teacher_without_school: 'teacher without school',
      teacher_classroom_school_mismatch: 'teacher/classroom school mismatch',
      teacher_classroom_grade_mismatch: 'teacher/classroom grade mismatch',
      inactive_teacher_assignment: 'inactive teacher assignment'
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
          role_mismatch: issue(role_mismatch_scope),
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
          )
        }
      )
    end

    private

    attr_reader :sample_limit

    def classroom_membership_scope
      ClassroomMembership
        .joins(:user, :classroom)
    end

    def classroom_sample_scope(scope)
      scope.select(
        'classroom_memberships.id AS classroom_membership_id',
        'classroom_memberships.user_id AS user_id',
        'classroom_memberships.classroom_id AS classroom_id',
        'classrooms.school_id AS classroom_school_id',
        'classroom_memberships.role AS role',
        'classroom_memberships.student_number AS student_number'
      )
    end

    def classroom_assignment_sample_scope(scope)
      scope.select(
        'classrooms.id AS classroom_id',
        'classrooms.teacher_id AS user_id',
        'classrooms.school_id AS classroom_school_id',
        'school_years.school_id AS teacher_school_id',
        'users.grade AS teacher_grade',
        'classrooms.grade AS classroom_grade'
      )
    end

    def role_mismatch_scope
      classroom_membership_scope.where(classroom_memberships: { role: 'student' })
        .where.not(users: { role: 'student' })
    end

    def teacher_without_school_scope
      Classroom
        .joins(:teacher)
        .left_joins(teacher: :school_year)
        .where.not(teacher_id: nil)
        .where(school_years: { id: nil })
    end

    def teacher_school_mismatch_scope
      Classroom
        .joins(teacher: :school_year)
        .where.not(teacher_id: nil)
        .where('school_years.school_id <> classrooms.school_id')
    end

    def teacher_grade_mismatch_scope
      Classroom.joins(teacher: :school_year)
        .where.not(teacher_id: nil)
        .where('users.grade IS NULL OR users.grade <> classrooms.grade')
    end

    def inactive_teacher_assignment_scope
      Classroom.joins(teacher: { school_year: :school })
        .where('users.active = FALSE OR school_years.status <> ? OR schools.active = FALSE', 'active')
    end

    def issue(scope, sample_scope: classroom_sample_scope(scope))
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
