FactoryBot.define do
  factory :classroom do
    association :school
    sequence(:name) { |n| "Classroom #{n}" }
    grade { 4 }
  end
end
