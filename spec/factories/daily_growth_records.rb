FactoryBot.define do
  factory :daily_growth_record do
    association :student
    classroom { student.classroom }
    recorded_on { Time.zone.today }
    reflection { nil }
    daily_virtue_configuration do
      classroom.daily_virtue_configurations.find_by(recorded_on: recorded_on) ||
        FactoryBot.build(:daily_virtue_configuration, classroom: classroom, recorded_on: recorded_on)
    end

    trait :with_score do
      after(:build) do |record|
        configuration = record.daily_virtue_configuration
        virtue = configuration.items.first&.virtue || record.classroom.virtues.first ||
          FactoryBot.build(:virtue, classroom: record.classroom)
        if configuration.new_record? && configuration.items.empty?
          configuration.items.build(virtue: virtue, name: virtue.name, position: virtue.position)
        end
        configuration.items.each do |item|
          record.daily_growth_scores.build(virtue: item.virtue, score: 3)
        end
      end
    end
  end
end
