FactoryBot.define do
  factory :daily_growth_record do
    association :student
    classroom { student.classroom }
    recorded_on { Time.zone.today }
    reflection { nil }

    trait :with_score do
      after(:build) do |record|
        virtue = record.classroom.virtues.first || FactoryBot.build(:virtue, classroom: record.classroom)
        record.daily_growth_scores.build(virtue:, score: 3)
      end
    end
  end
end
