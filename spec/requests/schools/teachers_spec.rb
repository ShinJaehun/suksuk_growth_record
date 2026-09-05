require 'rails_helper'

RSpec.describe 'School teachers compatibility endpoints', type: :request do
  let(:school) { create(:school) }
  let(:other_school) { create(:school) }
  let(:manager) do
    user = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager",
      annual_grade: 4,
      name: '학교 관리자')
    create(:school_membership, :manager, school: school, grade: 4,
                                                 user: user).user
  end
  let(:member) do
    user = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: 4,
      name: '소속 교사')
    create(:school_membership, school: school, grade: 4,
                               user: user).user
  end

  def teacher_params(email: 'new@example.com')
    { name: '새 교사', email: email, password: 'password123', password_confirmation: 'password123',
      gender: 'female', avatar_key: 'teacherF01' }
  end

  it 'shows only teachers and their single classroom in the manager school' do
    classroom = create(:classroom, school: school, grade: 4, teacher: member)
    outsider = create(:user, :teacher, :active_annual_teacher,
      annual_school: other_school, annual_grade: 4, name: '다른 학교 교사')
    sign_in manager

    get school_teachers_path(school)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(member.name, classroom.name)
    expect(response.body).not_to include(outsider.name)
  end

  it 'creates a teacher with grade and one classroom' do
    classroom = create(:classroom, school: school, grade: 4)
    sign_in manager

    post school_teachers_path(school), params: {
      user: teacher_params.except(:password, :password_confirmation).merge(
        login_id: " NewTeacher ",
        email: ""
      ),
      membership_grade: 4,
      classroom_id: classroom.id
    }

    teacher = User.find_by!(login_id: "newteacher")
    expect(response).to redirect_to(school_teachers_path(school))
    expect(teacher).to have_attributes(
      school_year: school.school_years.active.first,
      school_role: "member",
      grade: 4,
      email: nil,
      password_change_required: true
    )
    expect(teacher.school_membership).to be_nil
    expect(teacher.teacher_credential_events.where(action: "temporary_password_issued")).to exist
    expect(teacher.assigned_classroom).to eq(classroom)
  end


  it 'allows an annual manager without a membership to manage own-school teachers' do
    annual_manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
    sign_in annual_manager

    get school_teachers_path(school)

    expect(response).to have_http_status(:ok)
  end

  it 'moves and removes the single classroom assignment' do
    first = create(:classroom, school: school, grade: 4, teacher: member)
    second = create(:classroom, school: school, grade: 4)
    sign_in manager

    patch school_teacher_path(school, member), params: { membership_grade: 4, classroom_id: second.id }

    expect(first.reload.teacher).to be_nil
    expect(second.reload.teacher).to eq(member)

    patch school_teacher_path(school, member), params: { membership_grade: 4, classroom_id: '' }
    expect(second.reload.teacher).to be_nil
  end

  it 'rejects a classroom outside the URL school' do
    sign_in manager

    expect do
      post school_teachers_path(school), params: {
        user: teacher_params,
        membership_grade: 4,
        classroom_id: create(:classroom, school: other_school, grade: 4).id
      }
    end.not_to change(User.teacher, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'redirects an ordinary teacher without teacher-management permission' do
    sign_in member

    get school_teachers_path(school)

    expect(response).to redirect_to(root_path)
  end

  it 'returns not found for a manager outside the school scope' do
    other_manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: other_school,
      annual_school_role: "manager")
    create(:school_membership, :manager, school: other_school, user: other_manager)
    sign_in other_manager

    get school_teachers_path(school)

    expect(response).to have_http_status(:not_found)
  end
end
