class SchoolYear < ApplicationRecord
  belongs_to :school

  enum :status,
    {
      planning: "planning",
      active: "active",
      archived: "archived"
    },
    validate: true

  validates :year,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 9999
    },
    uniqueness: { scope: :school_id }
  validates :status,
    uniqueness: { scope: :school_id },
    if: :capacity_limited_status?

  private

  def capacity_limited_status?
    planning? || active?
  end
end
