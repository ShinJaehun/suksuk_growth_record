class Virtue < ApplicationRecord
  MAX_ACTIVE_PER_CLASSROOM = 5
  COLORS = {
    'blue' => '#2563eb',
    'green' => '#15803d',
    'violet' => '#7c3aed',
    'rose' => '#be123c',
    'orange' => '#c2410c',
    'teal' => '#0f766e',
    'magenta' => '#a21caf',
    'brown' => '#854d0e'
  }.freeze

  belongs_to :classroom
  has_many :daily_growth_scores, dependent: :restrict_with_error

  scope :active, -> { where(active: true) }
  scope :in_display_order, -> { order(:position, :id) }

  validates :name, presence: true
  validates :color_key, inclusion: { in: COLORS.keys }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :active_virtue_limit
  validate :active_color_unique_within_classroom
  validate :at_least_one_active_virtue, if: :deactivating?
  validate :classroom_must_not_change, on: :update
  before_validation :assign_creation_defaults, on: :create
  before_save :enforce_active_constraints_under_lock, if: :active_constraint_change?
  before_destroy :prevent_destroying_last_active_virtue, if: :active?

  def color_hex
    COLORS.fetch(color_key)
  end

  private

  def assign_creation_defaults
    return unless classroom

    self.position ||= classroom.virtues.maximum(:position).to_i + 1
    return if color_key.present?

    self.color_key = @automatically_assigned_color = unused_active_color
  end

  def unused_active_color
    used_colors = classroom.virtues.active.where.not(id: id).pluck(:color_key)
    (COLORS.keys - used_colors).first || COLORS.keys.first
  end

  def active_color_unique_within_classroom
    return unless active? && classroom && color_key.present?
    return if automatic_color_pending?
    return unless classroom.virtues.active.where(color_key: color_key).where.not(id: id).exists?

    errors.add(:color_key, :taken)
  end

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

  def active_constraint_change?
    new_record? || will_save_change_to_active? || (active? && will_save_change_to_color_key?)
  end

  def automatic_color_pending?
    new_record? && @automatically_assigned_color == color_key
  end

  def classroom_must_not_change
    return unless will_save_change_to_classroom_id?

    errors.add(:classroom, :immutable)
  end

  def enforce_active_constraints_under_lock
    classroom.lock!
    if automatic_color_pending?
      self.color_key = unused_active_color
      @automatically_assigned_color = nil
    end
    active_virtue_limit
    at_least_one_active_virtue if deactivating?
    active_color_unique_within_classroom if active?
    throw :abort if errors.any?
  end

  def prevent_destroying_last_active_virtue
    return if destroyed_by_association
    return if classroom.virtues.active.where.not(id: id).exists?

    errors.add(:active, :last_active)
    throw :abort
  end
end
