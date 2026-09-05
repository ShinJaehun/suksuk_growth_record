FactoryBot.define do
  factory :school_year do
    school
    year { 2026 }

    trait :active do
      status { "active" }
    end

    trait :archived do
      status { "archived" }
    end
  end
end
