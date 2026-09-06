module Admin
  class SchoolManagersController < Admin::BaseController
    before_action :set_school
    before_action :authorize_admin

    def create
      teacher = active_school_year.users.teacher.find(params.require(:user_id))
      manager_assigned = false

      User.transaction do
        active_school_year.lock!
        teacher.lock!

        if teacher.active?
          current_manager = active_school_year.users.teacher
            .where(school_role: "manager")
            .where.not(id: teacher.id)
            .first
          current_manager&.update!(school_role: "member")
          teacher.update!(school_role: "manager") unless teacher.school_manager?
          manager_assigned = true
        end
      end

      if manager_assigned
        render_manager_success("admin.school_managers.create.success")
      else
        redirect_to edit_school_path(@school),
          alert: t("admin.school_managers.errors.inactive_manager"),
          status: :see_other
      end
    end

    def destroy
      User.transaction do
        active_school_year.lock!
        teacher = active_school_year.users.teacher
          .find_by!(id: params[:user_id], school_role: "manager")
        teacher.update!(school_role: "member")
      end
      render_manager_success("admin.school_managers.destroy.success")
    end

    private

    def set_school
      @school = School.find(params[:school_id])
    end

    def authorize_admin
      authorize @school, :manage_managers?
    end

    def active_school_year
      @active_school_year ||= @school.school_years.active.first!
    end

    def render_manager_success(message_key)
      redirect_to edit_school_path(@school),
        notice: t(message_key),
        status: :see_other
    end
  end
end
