class Classrooms::VirtuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom
  before_action :set_active_virtue, only: %i[update deactivate]

  def index
    prepare_page
  end

  def create
    @virtue = @classroom.virtues.build(virtue_params)
    save_virtue
  end

  def update
    @virtue.assign_attributes(virtue_params)
    save_virtue
  end

  def deactivate
    @virtue.active = false
    save_virtue
  end

  private

  def set_classroom
    @classroom = policy_scope(Classroom).find(params[:classroom_id])
    authorize @classroom, :manage_growth_virtues?
  end

  def set_active_virtue
    @virtue = @classroom.virtues.active.find(params[:id])
  end

  def virtue_params
    params.require(:virtue).permit(:name, :color_key)
  end

  def save_virtue
    saved = @classroom.with_lock { @virtue.save }
    if saved
      redirect_to classroom_virtues_path(@classroom),
        notice: t("virtues.saved"), status: :see_other
    else
      prepare_page
      render :index, status: :unprocessable_content
    end
  end

  def prepare_page
    virtues = @classroom.virtues.in_display_order.to_a
    @active_virtues, @inactive_virtues = virtues.partition(&:active?)
    @active_count = @active_virtues.size
    @can_add_virtue = @active_count < Virtue::MAX_ACTIVE_PER_CLASSROOM
    @can_deactivate_virtue = @active_count > 1
    @active_virtues.map! { |virtue| virtue.id == @virtue&.id ? @virtue : virtue }
    @new_virtue = @virtue&.new_record? ? @virtue : @classroom.virtues.build
  end
end
