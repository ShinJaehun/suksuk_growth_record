class Virtue < ApplicationRecord
  MAX_ACTIVE_PER_CLASSROOM = 5

  belongs_to :classroom
  has_many :daily_growth_scores, dependent: :restrict_with_error

  scope :active, -> { where(active: true) }
  scope :in_display_order, -> { order(:position, :id) }

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :active_virtue_limit
  validate :at_least_one_active_virtue, if: :deactivating?
  validate :classroom_must_not_change, on: :update
  before_save :enforce_active_count_under_lock, if: :active_state_change?
  before_destroy :prevent_destroying_last_active_virtue, if: :active?

  private

  def active_virtue_limit
    return unless active? && (new_record? || will_save_change_to_active?)
    return unless classroom
    return unless classroom.virtues.active.where.not(id: id).count >= MAX_ACTIVE_PER_CLASSROOM

    errors.add(:active, :too_many)
  end

  def at_least_one_active_virtue
    return unless classroom.virtues.active.where.not(id: id).none?

    errors.add(:active, :last_active)
  end

  def deactivating?
    persisted? && will_save_change_to_active?(from: true, to: false)
  end

  def active_state_change?
    new_record? || will_save_change_to_active?
  end

  def classroom_must_not_change
    return unless will_save_change_to_classroom_id?

    errors.add(:classroom, :immutable)
  end

  def enforce_active_count_under_lock
    classroom.lock!
    active_virtue_limit
    at_least_one_active_virtue if deactivating?
    throw :abort if errors.any?
  end

  def prevent_destroying_last_active_virtue
    return if destroyed_by_association
    return if classroom.virtues.active.where.not(id: id).exists?

    errors.add(:active, :last_active)
    throw :abort
  end
end
