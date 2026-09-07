FactoryBot.define do
  factory :daily_growth_score do
    association :daily_growth_record
    virtue do
      daily_growth_record.classroom.virtues.first ||
        FactoryBot.build(:virtue, classroom: daily_growth_record.classroom)
    end
    score { 3 }
  end
end
