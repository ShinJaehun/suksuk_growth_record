class Student < ApplicationRecord
  BOY_AVATAR_KEYS = (1..23).map { |number| format("boy%02d", number) }.freeze
  GIRL_AVATAR_KEYS = (1..17).map { |number| format("girl%02d", number) }.freeze
  GENDERS = %w[boy girl].freeze
  AVATAR_KEYS_BY_GENDER = {
    "boy" => BOY_AVATAR_KEYS,
    "girl" => GIRL_AVATAR_KEYS
  }.freeze
  AVATAR_KEYS = (BOY_AVATAR_KEYS + GIRL_AVATAR_KEYS).freeze

  belongs_to :classroom
  has_many :daily_growth_records, dependent: :restrict_with_error

  has_secure_password :student_pin, validations: false

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :in_roster_order, -> { order(Arel.sql("student_number ASC NULLS LAST"), :name, :id) }

  validates :name, presence: true, length: { maximum: 30 }
  validates :gender, inclusion: { in: GENDERS }, allow_nil: true
  validates :student_number,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            allow_nil: true
  validates :student_number,
            uniqueness: { scope: :classroom_id, conditions: -> { active.where.not(student_number: nil) } },
            if: :numbered_active_student?
  validates :student_pin,
            format: { with: /\A\d{4}\z/, message: "must be 4 digits" },
            allow_blank: true
  validates :avatar_key, inclusion: { in: AVATAR_KEYS }, allow_nil: true
  validate :classroom_must_not_change, on: :update

  def self.avatar_keys_for(gender)
    AVATAR_KEYS_BY_GENDER.fetch(gender.to_s, [])
  end

  def inactive?
    !active?
  end

  def student_pin_configured?
    student_pin_digest.present?
  end

  private

  def numbered_active_student?
    active? && student_number.present?
  end

  def classroom_must_not_change
    return unless will_save_change_to_classroom_id?

    errors.add(:classroom, :immutable)
  end
end
