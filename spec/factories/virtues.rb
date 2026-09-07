FactoryBot.define do
  factory :virtue do
    association :classroom
    sequence(:name) { |number| "덕목 #{number}" }
    active { true }
    sequence(:position) { |number| number }
  end
end
