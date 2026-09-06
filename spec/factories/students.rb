FactoryBot.define do
  factory :student do
    association :classroom
    sequence(:name) { |number| "학생 #{number}" }
    student_number { nil }
    active { true }
    student_pin { "1234" }
    avatar_key { nil }
  end
end
