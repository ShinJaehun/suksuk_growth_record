class DailyVirtueConfigurationItem < ApplicationRecord
  belongs_to :daily_virtue_configuration, inverse_of: :items
  belongs_to :virtue

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :virtue_id, uniqueness: { scope: :daily_virtue_configuration_id }
  validate :virtue_matches_classroom
  validate :content_must_not_change, on: :update
  validate :configuration_must_be_new, on: :create
  before_destroy :prevent_destroy

  private

  def virtue_matches_classroom
    return unless virtue && daily_virtue_configuration
    return if virtue.classroom_id.present? && virtue.classroom_id == daily_virtue_configuration.classroom_id
    return if virtue.classroom_id.nil? && virtue.classroom == daily_virtue_configuration.classroom

    errors.add(:virtue, :classroom_mismatch)
  end

  def content_must_not_change
    %i[daily_virtue_configuration_id virtue_id name position].each do |attribute|
      errors.add(attribute, :immutable) if will_save_change_to_attribute?(attribute)
    end
  end

  def configuration_must_be_new
    return unless daily_virtue_configuration&.persisted?

    errors.add(:base, :immutable)
  end

  def prevent_destroy
    errors.add(:base, :immutable)
    throw :abort
  end
end
