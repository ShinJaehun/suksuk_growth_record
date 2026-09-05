module AnnualTeacherUsers
  class MappingBackfill
    Mapping = Data.define(:teacher_user_id, :login_id)
    Projection = Data.define(:user, :login_id, :school_role, :grade)
    Issue = Data.define(:code, :details) do
      def to_s
        return code.to_s if details.empty?

        "#{code}: #{details.map { |key, value| "#{key}=#{value}" }.join(' ')}"
      end
    end
    Result = Data.define(
      :target_school_year_id,
      :school_id,
      :requested_count,
      :mapped_count,
      :already_mapped_count,
      :errors,
      :warnings,
      :dry_run
    ) do
      def success?
        errors.empty?
      end
    end

    class PreflightFailed < StandardError; end
    class IntegrityError < StandardError; end

    def self.call(target_school_year_id:, rows:, dry_run: false)
      new(target_school_year_id:, rows:, dry_run:).call
    end

    def initialize(target_school_year_id:, rows:, dry_run: false)
      @raw_target_school_year_id = target_school_year_id
      @raw_rows = rows
      @dry_run = dry_run
      @errors = []
      @warnings = []
      @mappings = []
      @requested_count = raw_rows.is_a?(Array) ? raw_rows.size : 0
      @unmapped_projections = []
      @already_mapped_projections = []
    end

    def call
      validate_static_input
      return result if errors.any?

      dry_run ? validate_dry_run : perform_mapping
    rescue IntegrityError => e
      add_error(:post_write_integrity_failed, error: e.message)
      result
    rescue ActiveRecord::ActiveRecordError => e
      add_error(:persistence_failed, error: e.class.name)
      result
    end

    private

    attr_reader :raw_target_school_year_id, :raw_rows, :dry_run, :errors, :warnings,
                :mappings, :target_school_year, :unmapped_projections,
                :already_mapped_projections

    def validate_static_input
      @target_school_year_id = positive_integer(raw_target_school_year_id)
      add_error(:invalid_target_school_year_id) unless @target_school_year_id

      unless raw_rows.is_a?(Array) && raw_rows.any?
        add_error(:mapping_rows_required)
        return
      end

      raw_rows.each_with_index do |row, index|
        validate_mapping_row(row, index: index + 1)
      end

      validate_input_duplicates
    end

    def validate_mapping_row(row, index:)
      unless row.is_a?(Hash)
        add_error(:malformed_mapping_row, row: index)
        return
      end

      teacher_user_id = positive_integer(value_from(row, :teacher_user_id))
      login_id = value_from(row, :login_id)

      add_error(:invalid_teacher_user_id, row: index) unless teacher_user_id
      add_error(:invalid_login_id, row: index) unless valid_login_id?(login_id)
      return unless teacher_user_id && valid_login_id?(login_id)

      mappings << Mapping.new(teacher_user_id:, login_id:)
    end

    def validate_input_duplicates
      duplicate_values(mappings.map(&:teacher_user_id)).each do |user_id|
        add_error(:duplicate_teacher_user_id, teacher_user_id: user_id)
      end
      duplicate_values(mappings.map(&:login_id)).each do |login_id|
        add_error(:duplicate_login_id, login_id: login_id)
      end
    end

    def validate_dry_run
      validate_database_state(lock: false)
      result
    end

    def perform_mapping
      User.transaction do
        validate_database_state(lock: true)
        raise PreflightFailed if errors.any?

        unmapped_projections.each { |projection| persist_projection(projection) }
        verify_written_projections!
      end

      result
    rescue PreflightFailed
      result
    end

    def validate_database_state(lock:)
      reset_database_state
      @target_school_year = find_target_school_year(lock:)
      return unless target_school_year

      add_error(:target_school_year_not_active, status: target_school_year.status) unless target_school_year.active?
      return if errors.any?

      users = load_users(lock:)
      memberships = load_memberships(users.values, lock:)
      projections = build_projections(users:, memberships:)

      validate_existing_login_ids(projections)
      validate_manager_cardinality(projections)
      collect_case_fold_warnings(projections)
    end

    def reset_database_state
      @unmapped_projections = []
      @already_mapped_projections = []
    end

    def find_target_school_year(lock:)
      scope = SchoolYear.where(id: @target_school_year_id)
      scope = scope.lock if lock
      scope.first.tap do |school_year|
        add_error(:target_school_year_not_found, school_year_id: @target_school_year_id) unless school_year
      end
    end

    def load_users(lock:)
      scope = User.where(id: mappings.map(&:teacher_user_id)).order(:id)
      scope = scope.lock if lock
      users = scope.index_by(&:id)

      (mappings.map(&:teacher_user_id) - users.keys).each do |user_id|
        add_error(:teacher_not_found, teacher_user_id: user_id)
      end
      users
    end

    def load_memberships(users, lock:)
      scope = SchoolMembership.where(user_id: users.map(&:id)).order(:id)
      scope = scope.lock if lock
      scope.index_by(&:user_id)
    end

    def build_projections(users:, memberships:)
      mappings.filter_map do |mapping|
        user = users[mapping.teacher_user_id]
        next unless user

        membership = memberships[user.id]
        unless user.teacher?
          add_error(:user_not_teacher, teacher_user_id: user.id)
          next
        end
        unless membership
          add_error(:school_membership_missing, teacher_user_id: user.id)
          next
        end
        if membership.school_id != target_school_year.school_id
          add_error(:school_mismatch, teacher_user_id: user.id, school_id: membership.school_id)
          next
        end
        unless %w[member manager].include?(membership.role)
          add_error(:invalid_membership_role, teacher_user_id: user.id, role: membership.role)
          next
        end
        unless membership.grade.nil? || (1..6).cover?(membership.grade)
          add_error(:invalid_membership_grade, teacher_user_id: user.id, grade: membership.grade)
          next
        end

        projection = Projection.new(
          user:,
          login_id: mapping.login_id,
          school_role: membership.role,
          grade: membership.grade
        )
        classify_shadow_state(projection)
        projection
      end
    end

    def classify_shadow_state(projection)
      user = projection.user
      if [user.school_year_id, user.login_id, user.school_role, user.grade].all?(&:nil?)
        unmapped_projections << projection
      elsif completed_mapping?(projection)
        already_mapped_projections << projection
      else
        add_error(:conflicting_shadow_state, teacher_user_id: user.id)
      end
    end

    def completed_mapping?(projection)
      user = projection.user
      user.school_year_id == target_school_year.id &&
        user.login_id == projection.login_id &&
        user.school_role == projection.school_role &&
        user.grade == projection.grade
    end

    def validate_existing_login_ids(projections)
      projections_by_login_id = projections.index_by(&:login_id)
      User.where(school_year_id: target_school_year.id, login_id: projections_by_login_id.keys).find_each do |owner|
        projection = projections_by_login_id[owner.login_id]
        next if owner.id == projection.user.id && completed_mapping?(projection)

        add_error(
          :login_id_collision,
          login_id: owner.login_id,
          teacher_user_id: projection.user.id,
          owner_user_id: owner.id
        )
      end
    end

    def validate_manager_cardinality(projections)
      manager_ids = User.where(
        school_year_id: target_school_year.id,
        role: 'teacher',
        school_role: 'manager'
      ).pluck(:id)
      manager_ids.concat(projections.select do |projection|
        projection.school_role == 'manager'
      end.map { |projection| projection.user.id })
      manager_ids.uniq!
      return if manager_ids.size <= 1

      add_error(:manager_conflict, teacher_user_ids: manager_ids.sort.join(','))
    end

    def collect_case_fold_warnings(projections)
      login_owners = User.where(school_year_id: target_school_year.id)
                         .where.not(login_id: nil)
                         .pluck(:id, :login_id)
      login_owners.concat(projections.map { |projection| [projection.user.id, projection.login_id] })

      login_owners.group_by { |_user_id, login_id| login_id.downcase }.each_value do |entries|
        next unless entries.map(&:last).uniq.size > 1

        add_warning(
          :case_fold_login_id_collision,
          login_ids: entries.map(&:last).uniq.sort.join(','),
          teacher_user_ids: entries.map(&:first).uniq.sort.join(',')
        )
      end
    end

    def persist_projection(projection)
      projection.user.update_columns(
        school_year_id: target_school_year.id,
        login_id: projection.login_id,
        school_role: projection.school_role,
        grade: projection.grade
      )
    end

    def verify_written_projections!
      expected = (unmapped_projections + already_mapped_projections).to_h do |projection|
        [
          projection.user.id,
          [target_school_year.id, projection.login_id, projection.school_role, projection.grade]
        ]
      end
      actual = User.where(id: expected.keys).pluck(:id, :school_year_id, :login_id, :school_role, :grade).to_h do |row|
        [row.first, row.drop(1)]
      end

      raise IntegrityError, 'annual teacher mapping integrity check failed' unless actual == expected
    end

    def result
      Result.new(
        target_school_year_id: @target_school_year_id,
        school_id: target_school_year&.school_id,
        requested_count: @requested_count,
        mapped_count: errors.empty? ? unmapped_projections.size : 0,
        already_mapped_count: errors.empty? ? already_mapped_projections.size : 0,
        errors: errors.dup.freeze,
        warnings: warnings.dup.freeze,
        dry_run:
      )
    end

    def value_from(row, key)
      row[key] || row[key.to_s]
    end

    def positive_integer(value)
      return value if value.is_a?(Integer) && value.positive?

      value.to_i if value.is_a?(String) && value.match?(/\A[1-9]\d*\z/)
    end

    def valid_login_id?(login_id)
      login_id.is_a?(String) && login_id.present? && login_id.strip == login_id
    end

    def duplicate_values(values)
      values.tally.select { |_value, count| count > 1 }.keys
    end

    def add_error(code, **details)
      errors << Issue.new(code:, details:)
    end

    def add_warning(code, **details)
      warnings << Issue.new(code:, details:)
    end
  end
end
