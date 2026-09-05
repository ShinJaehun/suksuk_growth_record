module AnnualTeacherUsers
  class CutoverReadiness
    Issue = Data.define(:code, :user_ids) do
      def to_s
        [code, user_ids.presence&.join(",")].compact.join(": ")
      end
    end
    Result = Data.define(:ready, :reconciled_count, :normalized_count, :issues, :dry_run) do
      def ready? = ready
    end

    def self.call(dry_run: true)
      new(dry_run:).call
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
      @issues = []
      @reconciled_count = 0
      @normalized_count = 0
      @projected_users = {}
    end

    def call
      school_year_ids.each { |id| reconcile_school_year(id) }
      normalization_candidates = audit_all_users
      normalize_login_ids(normalization_candidates) if issues.empty?
      result
    rescue ActiveRecord::ActiveRecordError => error
      issue(:persistence_failed, [])
      result
    end

    private

    attr_reader :dry_run, :issues

    def school_year_ids
      User.teacher.where.not(school_year_id: nil).joins(:school_membership)
        .distinct.order(:school_year_id).pluck(:school_year_id)
    end

    def reconcile_school_year(id)
      return reconcile_dry_run(id) if dry_run

      committed_count = 0
      committed_users = {}
      SchoolYear.transaction do
        issue_count_before_batch = issues.size
        changes = reconciliation_changes(id, lock: true)
        raise ActiveRecord::Rollback if issues.size > issue_count_before_batch

        changes.each do |user, membership|
          user.update_columns(school_role: membership.role, grade: membership.grade, updated_at: Time.current)
          committed_users[user.id] = user
          committed_count += 1
        end
      end
      @projected_users.merge!(committed_users)
      @reconciled_count += committed_count
    rescue ActiveRecord::ActiveRecordError
      issue(:reconciliation_persistence_failed, [])
    end

    def reconcile_dry_run(id)
      issue_count_before_batch = issues.size
      changes = reconciliation_changes(id, lock: false)
      return if issues.size > issue_count_before_batch

      changes.each do |user, membership|
        user.assign_attributes(school_role: membership.role, grade: membership.grade)
        @projected_users[user.id] = user
      end
      @reconciled_count += changes.size
    end

    def reconciliation_changes(id, lock:)
      school_year_scope = SchoolYear.where(id: id)
      school_year_scope = school_year_scope.lock if lock
      school_year = school_year_scope.first!
      membership_user_ids = SchoolMembership.select(:user_id)
      users_scope = User.teacher.where(school_year_id: id, id: membership_user_ids).order(:id)
      users_scope = users_scope.lock if lock
      users = users_scope.to_a
      memberships_scope = SchoolMembership.where(user_id: users.map(&:id)).order(:id)
      memberships_scope = memberships_scope.lock if lock
      memberships = memberships_scope.index_by(&:user_id)

      users.filter_map do |user|
        membership = memberships[user.id]
        unless valid_projection?(school_year, membership)
          issue(:invalid_legacy_projection, [user.id])
          next
        end
        [user, membership] if user.school_role != membership.role || user.grade != membership.grade
      end
    end

    def valid_projection?(school_year, membership)
      membership && membership.school_id == school_year.school_id &&
        %w[member manager].include?(membership.role) &&
        (membership.grade.nil? || (1..6).cover?(membership.grade))
    end

    def audit_all_users
      unmapped_legacy_ids = User.teacher.joins(:school_membership).where(school_year_id: nil).pluck(:id)
      issue(:unmapped_legacy_teacher, unmapped_legacy_ids) if unmapped_legacy_ids.any?

      annual_teachers = User.teacher.order(:id).map do |user|
        @projected_users.fetch(user.id, user)
      end
      incomplete = annual_teachers.reject do |user|
        user.school_year_id.present? && user.login_id.present? &&
          user.school_role.in?(%w[member manager]) &&
          (user.grade.nil? || (1..6).cover?(user.grade))
      end
      issue(:incomplete_annual_teacher, incomplete.map(&:id)) if incomplete.any?

      whitespace = annual_teachers.select { |user| user.login_id.present? && user.login_id != user.login_id.strip }
      issue(:stored_login_id_whitespace, whitespace.map(&:id)) if whitespace.any?

      collision_ids = annual_teachers.group_by { |user| [user.school_year_id, user.login_id&.downcase] }
        .values.select { |users| users.first.login_id.present? && users.size > 1 }.flatten.map(&:id)
      issue(:normalized_login_id_collision, collision_ids) if collision_ids.any?

      managers = annual_teachers.select { |user| user.school_role == "manager" }
      manager_conflicts = managers.group_by(&:school_year_id).values.select { |users| users.size > 1 }.flatten.map(&:id)
      issue(:manager_conflict, manager_conflicts) if manager_conflicts.any?

      invalid_non_teachers = User.where.not(role: "teacher").where(
        "school_year_id IS NOT NULL OR login_id IS NOT NULL OR school_role IS NOT NULL OR grade IS NOT NULL"
      ).pluck(:id)
      issue(:non_teacher_annual_fields, invalid_non_teachers) if invalid_non_teachers.any?

      annual_teachers.select { |user| user.login_id.present? && user.login_id != user.login_id.downcase }
    end

    def normalize_login_ids(candidates)
      if dry_run
        @normalized_count = candidates.size
        return
      end

      committed_count = 0
      User.transaction do
        locked_users = User.where(id: candidates.map(&:id)).order(:id).lock.to_a
        locked_users.each do |user|
          user.update_columns(login_id: user.login_id.downcase, updated_at: Time.current)
          committed_count += 1
        end
      end
      @normalized_count += committed_count
    rescue ActiveRecord::ActiveRecordError
      issue(:normalization_persistence_failed, [])
    end

    def issue(code, user_ids) = issues << Issue.new(code:, user_ids: user_ids.sort)

    def result
      Result.new(
        ready: issues.empty?,
        reconciled_count: @reconciled_count,
        normalized_count: @normalized_count,
        issues:,
        dry_run:
      )
    end
  end
end
