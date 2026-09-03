module SchoolWorkspacePrepareable
  extend ActiveSupport::Concern

  private

  def prepare_school_workspace
    prepare_school_overview
  end

  def prepare_school_overview
    @classroom_count = @school.classrooms.count
    @teacher_count = @school.school_memberships.joins(:user).where(users: { active: true }).count
    @managers = @school.school_memberships.manager.joins(:user).includes(:user).where(users: { active: true }).map(&:user)
  end

  def prepare_school_settings
    @managers = @school.school_memberships.manager.includes(:user).order(:id)
    @manager_candidates = @school.school_memberships
      .joins(:user).includes(:user).where(users: { active: true })
      .order(:role, :id)
      .map(&:user)
  end
end
