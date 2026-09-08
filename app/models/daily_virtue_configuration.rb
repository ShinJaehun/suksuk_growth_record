class DailyVirtueConfiguration < ApplicationRecord
  belongs_to :classroom
  has_many :items, -> { order(:position, :id) },
    class_name: "DailyVirtueConfigurationItem", inverse_of: :daily_virtue_configuration,
    autosave: true, dependent: :restrict_with_error
  has_many :daily_growth_records, dependent: :restrict_with_error

  validates :recorded_on, presence: true, uniqueness: { scope: :classroom_id }
  validates :items, presence: true
  validate :identity_must_not_change, on: :update

  private

  def identity_must_not_change
    errors.add(:classroom, :immutable) if will_save_change_to_classroom_id?
    errors.add(:recorded_on, :immutable) if will_save_change_to_recorded_on?
  end
end
