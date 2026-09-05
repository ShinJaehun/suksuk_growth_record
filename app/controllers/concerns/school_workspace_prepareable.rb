module SchoolWorkspacePrepareable
  extend ActiveSupport::Concern

  private

  def prepare_school_workspace
    prepare_school_overview
  end

  def prepare_school_overview
    @classroom_count = @school.classrooms.count
    @teacher_count = active_school_teachers.active.count
    @managers = active_school_teachers.active.where(school_role: "manager").order(:id)
  end

  def prepare_school_settings
    @managers = active_school_teachers.where(school_role: "manager").order(:id)
    @manager_candidates = active_school_teachers.active.order(:school_role, :id)
  end

  def active_school_teachers
    school_year = @school.school_years.active.first
    school_year ? school_year.users.teacher : User.none
  end
end
