FactoryBot.define do
  factory :daily_virtue_configuration do
    classroom
    recorded_on { Time.zone.today }

    trait :with_items do
      after(:build) do |configuration|
        configuration.classroom.virtues.active.in_display_order.each do |virtue|
          configuration.items.build(virtue: virtue, name: virtue.name, position: virtue.position)
        end
      end
    end
  end
end
