FactoryBot.define do
  factory :classroom do
    transient do
      annual_school { nil }
      teacher { nil }
    end

    school_year do
      school = annual_school || FactoryBot.create(:school)
      school.school_years.active.first ||
        FactoryBot.create(:school_year, :active, school: school)
    end
    sequence(:class_label) { |n| n.to_s }
    grade { 4 }

    after(:create) do |classroom, evaluator|
      if evaluator.teacher
        create(:homeroom_assignment, classroom: classroom, teacher: evaluator.teacher)
      end
    end
  end
end
