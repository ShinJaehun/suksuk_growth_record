module Admin
  class SchoolManagersController < Admin::BaseController
    before_action :set_school
    before_action :authorize_admin

    def create
      teacher = active_school_year.users.teacher.find(params.require(:user_id))
      unless teacher.active?
        return redirect_to edit_school_path(@school),
          alert: t("school_memberships.errors.inactive_manager"),
          status: :see_other
      end

      existing_manager = active_school_year.users.teacher
        .where(school_role: "manager")
        .where.not(id: teacher.id)
        .exists?
      if existing_manager
        return redirect_to edit_school_path(@school), status: :see_other
      end

      User.transaction do
        active_school_year.lock!
        if active_school_year.users.teacher.where(school_role: "manager").where.not(id: teacher.id).exists?
          raise ActiveRecord::Rollback
        end
        teacher.update!(school_role: "manager")
      end

      if teacher.reload.school_manager?
        render_manager_success("admin.school_managers.create.success")
      else
        redirect_to edit_school_path(@school), status: :see_other
      end
    end

    def destroy
      teacher = active_school_year.users.teacher.find_by!(id: params[:user_id], school_role: "manager")
      teacher.update!(school_role: "member")
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
