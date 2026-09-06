require 'rails_helper'

RSpec.describe 'Admin teacher school and classroom assignments', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let(:other_school) { create(:school) }
  let!(:school_year) { create(:school_year, :active, school: school) }
  let!(:other_school_year) { create(:school_year, :active, school: other_school) }

  def teacher_params(email: 'teacher@example.com', login_id: ' AnnualTeacher ')
    { name: '교사', email: email, login_id: login_id, gender: 'female', avatar_key: 'teacherF01' }
  end

  it 'creates a teacher with school, grade, and one classroom' do
    classroom = create(:classroom, annual_school: school, grade: 4)
    sign_in admin

    post admin_teachers_path, params: {
      user: teacher_params,
      school_id: school.id,
      membership_grade: 4,
      classroom_id: classroom.id
    }

    teacher = User.find_by!(email: 'teacher@example.com')
    expect(response).to redirect_to(admin_teachers_path)
    expect(teacher).to have_attributes(
      role: 'teacher',
      school_year: school_year,
      login_id: 'annualteacher',
      school_role: 'member',
      grade: 4,
      password_change_required: true
    )
    expect(teacher.annual_school).to eq(school)
    expect(teacher.assigned_classroom).to eq(classroom)
  end

  it 'creates a teacher with school and grade but no classroom' do
    sign_in admin

    post admin_teachers_path, params: {
      user: teacher_params,
      school_id: school.id,
      membership_grade: 4,
      classroom_id: ''
    }

    teacher = User.find_by!(email: 'teacher@example.com')
    expect(teacher).to have_attributes(
      school_year: school_year,
      login_id: 'annualteacher',
      school_role: 'member',
      grade: 4
    )
    expect(teacher.assigned_classroom).to be_nil
  end

  it 'moves and removes a single classroom assignment' do
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: 'manager',
      annual_grade: 4)
    first = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    second = create(:classroom, annual_school: school, grade: 4)
    sign_in admin

    patch admin_teacher_path(teacher), params: {
      school_id: school.id, membership_grade: 4, classroom_id: second.id
    }

    expect(first.reload.teacher).to be_nil
    expect(second.reload.teacher).to eq(teacher)
    expect(teacher.reload.school_role).to eq('manager')

    patch admin_teacher_path(teacher), params: {
      school_id: school.id, membership_grade: 4, classroom_id: ''
    }
    expect(second.reload.teacher).to be_nil
  end

  it 'rejects changing the SchoolYear of a persisted annual teacher' do
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: 'manager',
      annual_grade: 4)
    old_classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    new_classroom = create(:classroom, annual_school: other_school, grade: 5)
    sign_in admin

    patch admin_teacher_path(teacher), params: {
      school_id: other_school.id,
      membership_grade: 5,
      classroom_id: new_classroom.id,
      user: { name: '변경된 이름' }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(teacher.reload).to have_attributes(
      school_year: school_year,
      grade: 4,
      school_role: 'manager'
    )
    expect(teacher.name).not_to eq('변경된 이름')
    expect(old_classroom.reload.teacher).to eq(teacher)
    expect(new_classroom.reload.teacher).to be_nil
  end

  it 'rejects invalid classroom choices without partial changes' do
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    sign_in admin

    patch admin_teacher_path(teacher), params: {
      school_id: school.id,
      membership_grade: 4,
      classroom_id: create(:classroom, annual_school: other_school, grade: 4).id
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(teacher.reload).to have_attributes(school_year: school_year, grade: 4)
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it 'rejects removing the annual school and preserves the assignment' do
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    sign_in admin

    patch admin_teacher_path(teacher), params: {
      school_id: '', membership_grade: '', classroom_id: ''
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(teacher.reload).to have_attributes(
      school_year: school_year,
      grade: 4,
      school_role: 'member'
    )
    expect(classroom.reload.teacher).to eq(teacher)
  end
end
