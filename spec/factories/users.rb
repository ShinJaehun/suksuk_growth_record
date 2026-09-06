FactoryBot.define do
  sequence(:annual_teacher_login_id) { |n| "teacher#{n}" }

  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    name { "Test User" }
    trait :teacher do
      role { "teacher" }
      sequence(:email) { |n| "teacher#{n}@example.com" }
      password { "password123" }
    end

    trait :active_annual_teacher do
      transient do
        annual_school { nil }
        annual_school_role { "member" }
        annual_grade { nil }
      end

      school_year do
        raise ArgumentError, "annual_school is required" unless annual_school

        annual_school.school_years.active.first ||
          FactoryBot.create(:school_year, :active, school: annual_school)
      end
      login_id { generate(:annual_teacher_login_id) }
      school_role { annual_school_role }
      grade { annual_grade }
    end

    trait :admin do
      role { "admin" }
      sequence(:email) { |n| "admin#{n}@example.com" }
      password { "password123" }
    end
  end
end
