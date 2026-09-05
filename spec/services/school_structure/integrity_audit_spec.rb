require 'rails_helper'

RSpec.describe SchoolStructure::IntegrityAudit do
  def assign_without_validation(classroom, teacher)
    classroom.update_columns(teacher_id: teacher.id)
  end

  def insert_school_membership!(user:, school:)
    membership = SchoolMembership.new(
      user: user,
      school: school,
      role: :member
    )
    membership.save!(validate: false)
    membership
  end

  it 'is clean for a valid teacher assignment' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: 4)
    create(:classroom, school: school, grade: 4, teacher: teacher)

    result = described_class.call

    expect(result).to be_clean
    expect(result.issue_count).to eq(0)
  end

  it 'finds a teacher assigned to a classroom in another school' do
    teacher_school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: teacher_school, annual_grade: 4)
    classroom = create(:classroom, grade: 4)
    assign_without_validation(classroom, teacher)

    result = described_class.call

    expect(result.count_for(:teacher_classroom_school_mismatch)).to eq(1)
    expect(result.samples_for(:teacher_classroom_school_mismatch)).to include(
      include('classroom_id' => classroom.id, 'user_id' => teacher.id,
              'teacher_school_id' => teacher_school.id)
    )
  end

  it 'finds a teacher assigned to a classroom in another grade' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school, annual_grade: 4)
    classroom = create(:classroom, school: school, grade: 5)
    assign_without_validation(classroom, teacher)

    result = described_class.call

    expect(result.count_for(:teacher_classroom_grade_mismatch)).to eq(1)
    expect(result.samples_for(:teacher_classroom_grade_mismatch)).to include(
      include('classroom_id' => classroom.id, 'teacher_grade' => 4, 'classroom_grade' => 5)
    )
  end

  it 'finds student classroom memberships whose user is not a student' do
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: create(:school))
    membership = build(:classroom_membership, user: teacher, role: 'student')
    membership.save!(validate: false)

    result = described_class.call

    expect(result.count_for(:role_mismatch)).to eq(1)
    expect(result.samples_for(:role_mismatch)).to include(
      include('classroom_membership_id' => membership.id, 'user_id' => teacher.id)
    )
  end

  it 'finds an inactive teacher assignment' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school, annual_grade: 4)
    classroom = create(:classroom, school: school, grade: 4)
    teacher.update_columns(active: false)
    assign_without_validation(classroom, teacher)

    result = described_class.call

    expect(result.count_for(:inactive_teacher_assignment)).to eq(1)
    expect(result.samples_for(:inactive_teacher_assignment)).to include(
      include('classroom_id' => classroom.id, 'user_id' => teacher.id)
    )
  end

  it 'finds a school membership whose user is not a teacher' do
    student = create(:user, :student)
    school = create(:school)
    insert_school_membership!(user: student, school: school)

    result = described_class.call

    expect(result.count_for(:invalid_school_membership_user_role)).to eq(1)
    expect(result.samples_for(:invalid_school_membership_user_role)).to include(
      include('user_id' => student.id, 'teacher_school_id' => school.id, 'user_role' => 'student')
    )
  end

  it 'limits samples without changing the total issue count' do
    school = create(:school)
    2.times do
      teacher = create(:user, :teacher, :active_annual_teacher,
        annual_school: school, annual_grade: 4)
      assign_without_validation(create(:classroom, grade: 5), teacher)
    end

    result = described_class.call(sample_limit: 1)

    expect(result.count_for(:teacher_classroom_grade_mismatch)).to eq(2)
    expect(result.samples_for(:teacher_classroom_grade_mismatch).size).to eq(1)
  end
end
