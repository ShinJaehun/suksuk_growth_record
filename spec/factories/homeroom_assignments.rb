FactoryBot.define do
  factory :homeroom_assignment do
    classroom
    teacher do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: classroom.school_year.school,
        annual_grade: classroom.grade)
    end
    started_on { Date.current }

    trait :ended do
      ended_on { started_on }
    end
  end
end
