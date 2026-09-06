require 'rails_helper'

RSpec.describe SchoolStructure::IntegrityAudit do
  def assign_without_validation(classroom, teacher)
    assignment = HomeroomAssignment.new(
      classroom: classroom,
      teacher: teacher,
      started_on: Date.current
    )
    assignment.save!(validate: false)
  end

  it 'is clean for a valid teacher assignment' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school,
                     annual_grade: 4)
    create(:classroom, annual_school: school, grade: 4, teacher: teacher)

    result = described_class.call

    expect(result).to be_clean
    expect(result.issue_count).to eq(0)
  end

  it 'is clean for a valid planning SchoolYear assignment' do
    school = create(:school)
    school_year = create(:school_year, :planning, school: school)
    classroom = create(:classroom, school_year: school_year, grade: 4)
    teacher = create(
      :user,
      :teacher,
      school_year: school_year,
      login_id: 'planning-audit-teacher',
      school_role: 'member',
      grade: 4
    )
    create(:homeroom_assignment, classroom: classroom, teacher: teacher)

    result = described_class.call

    expect(result).to be_clean
    expect(result.issue_count).to eq(0)
  end

  it 'does not report preserved archived assignment history for an inactive teacher' do
    assignment = create(:homeroom_assignment)
    assignment.classroom.school_year.update!(status: 'archived')
    assignment.teacher.update!(active: false)

    result = described_class.call

    expect(result.count_for(:inactive_teacher_assignment)).to eq(0)
  end

  it 'finds a teacher assigned to a classroom in another school year' do
    teacher_school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: teacher_school, annual_grade: 4)
    classroom = create(:classroom, grade: 4)
    assign_without_validation(classroom, teacher)

    result = described_class.call

    expect(result.count_for(:teacher_classroom_school_mismatch)).to eq(1)
    expect(result.samples_for(:teacher_classroom_school_mismatch)).to include(
      include('classroom_id' => classroom.id, 'user_id' => teacher.id,
              'teacher_school_year_id' => teacher.school_year_id,
              'classroom_school_year_id' => classroom.school_year_id)
    )
  end

  it 'finds a teacher assigned to a classroom in another grade' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school, annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 5)
    assign_without_validation(classroom, teacher)

    result = described_class.call

    expect(result.count_for(:teacher_classroom_grade_mismatch)).to eq(1)
    expect(result.samples_for(:teacher_classroom_grade_mismatch)).to include(
      include('classroom_id' => classroom.id, 'teacher_grade' => 4, 'classroom_grade' => 5)
    )
  end

  it 'allows suppressing samples without changing the total issue count' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school, annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 5)
    assign_without_validation(classroom, teacher)

    result = described_class.call(sample_limit: 0)

    expect(result.count_for(:teacher_classroom_grade_mismatch)).to eq(1)
    expect(result.samples_for(:teacher_classroom_grade_mismatch)).to be_empty
  end

  it 'finds an inactive teacher assignment' do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: school, annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4)
    assign_without_validation(classroom, teacher)
    teacher.update_columns(active: false)

    result = described_class.call

    expect(result.count_for(:inactive_teacher_assignment)).to eq(1)
    expect(result.samples_for(:inactive_teacher_assignment)).to include(
      include('classroom_id' => classroom.id, 'user_id' => teacher.id)
    )
  end

  it 'finds an assignment whose user is not a teacher' do
    classroom = create(:classroom)
    admin = create(:user, :admin)
    assign_without_validation(classroom, admin)

    result = described_class.call

    expect(result.count_for(:invalid_homeroom_assignment_teacher_role)).to eq(1)
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
