require 'rails_helper'

RSpec.describe 'Teacher operations', type: :request do
  let(:school) { create(:school) }
  let(:manager) { create(:school_membership, :manager, school: school).user }

  it 'allows admins and managers but rejects regular teachers' do
    sign_in create(:user, :admin)
    get teachers_path
    expect(response).to have_http_status(:ok)
    sign_in manager
    get teachers_path
    expect(response).to have_http_status(:ok)
    sign_in create(:school_membership, school: school).user
    get teachers_path
    expect(response).to redirect_to(root_path)
  end

  it "limits a manager's index and direct lookup to their school" do
    own_teacher = create(:school_membership, school: school).user
    other_teacher = create(:school_membership, school: create(:school)).user
    sign_in manager
    get teachers_path
    expect(response.body).to include(own_teacher.email)
    expect(response.body).not_to include(other_teacher.email, 'name="school_id"')
    get edit_teacher_path(other_teacher)
    expect(response).to have_http_status(:not_found)
  end

  it "shows only the manager's school and active classrooms on the new form" do
    own_classroom = create(:classroom, school: school, name: '우리 학교 학급')
    other_school = create(:school, name: '다른 학교')
    other_classroom = create(:classroom, school: other_school, name: '다른 학교 학급')

    sign_in manager
    get new_teacher_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(school.name)
    expect(response.body).to include(own_classroom.name)

    expect(response.body).not_to include(other_school.name)
    expect(response.body).not_to include(other_classroom.name)
    expect(response.body).not_to include('name="school_id"')
  end

  it 'creates a teacher with an initial password and multiple classrooms' do
    classrooms = create_list(:classroom, 2, school: school)
    sign_in manager
    post teachers_path, params: {
      user: { name: '새 선생님', email: 'new-teacher@example.com', password: 'password123',
              password_confirmation: 'password123', gender: 'female', avatar_key: 'teacherF01' },
      classroom_ids: classrooms.map(&:id)
    }
    teacher = User.find_by!(email: 'new-teacher@example.com')
    expect(teacher.valid_password?('password123')).to eq(true)
    expect(teacher.school).to eq(school)
    expect(teacher.classroom_memberships.teacher.pluck(:classroom_id)).to match_array(classrooms.map(&:id))
    expect(teacher.avatar_key).to eq('teacherF01')
  end

  it 'updates profiles without changing password, role, or school' do
    teacher = create(:school_membership, school: school).user
    teacher.update!(password: 'password123')
    sign_in manager
    patch teacher_path(teacher), params: {
      user: { name: '수정 선생님', email: 'updated@example.com', gender: 'male', avatar_key: 'teacherM01',
              password: 'changed-password', password_confirmation: 'changed-password', role: 'admin' },
      school_id: create(:school).id,
      classroom_ids: []
    }
    expect(response).to redirect_to(teachers_path)
    teacher.reload
    expect(teacher).to have_attributes(name: '수정 선생님', email: 'updated@example.com', role: 'teacher', school: school)
    expect(teacher.valid_password?('password123')).to eq(true)
  end

  it 'reuses the avatar picker and normalizes avatar when gender changes' do
    teacher = create(
      :school_membership,
      school: school,
      user: create(:user, :teacher, gender: 'female', avatar_key: 'teacherF01')
    ).user
    sign_in manager

    get edit_teacher_path(teacher)
    expect(response.body).to include(
      'data-controller="teacher-avatar-preview"',
      'data-teacher-avatar-preview-target="avatarKey"',
      'data-action="teacher-avatar-preview#select"'
    )
    expect(response.body).not_to include('name="user[password]"')

    patch teacher_path(teacher), params: {
      user: { name: teacher.name, email: teacher.email, gender: 'male' },
      classroom_ids: []
    }

    expect(teacher.reload.avatar_key).to be_in(User::TEACHER_MALE_AVATAR_KEYS)
  end

  it 'lets a manager update their own profile' do
    sign_in manager
    patch teacher_path(manager),
          params: { user: { name: '대표 수정', email: 'manager-updated@example.com' }, classroom_ids: [] }
    expect(manager.reload).to have_attributes(name: '대표 수정', email: 'manager-updated@example.com')
  end

  it 'rejects outside-school and inactive classroom assignments' do
    teacher = create(:school_membership, school: school).user
    sign_in manager
    [create(:classroom, school: create(:school)), create(:classroom, school: school, active: false)].each do |classroom|
      patch teacher_path(teacher),
            params: { user: { name: teacher.name, email: teacher.email }, classroom_ids: [classroom.id] }
      expect(response).to have_http_status(:unprocessable_content)
      expect(teacher.classroom_memberships.teacher).to be_empty
    end
  end

  it 'preserves an existing inactive classroom assignment' do
    teacher = create(:school_membership, school: school).user
    classroom = create(:classroom, school: school)
    assignment = create(:classroom_membership, user: teacher, classroom: classroom, role: :teacher)
    classroom.update!(active: false)
    sign_in manager
    patch teacher_path(teacher), params: { user: { name: '보존 선생님', email: teacher.email }, classroom_ids: [] }
    expect(ClassroomMembership.exists?(assignment.id)).to eq(true)
  end

  it 'enforces lifecycle permissions and preserves memberships' do
    member = create(:school_membership, school: school)
    assignment = create(:classroom_membership, user: member.user, classroom: create(:classroom, school: school),
                                               role: :teacher)
    other_manager = create(:school_membership, :manager, school: school)
    sign_in manager
    patch deactivate_teacher_path(member.user)
    expect(member.user.reload).to be_inactive
    expect(SchoolMembership.exists?(member.id)).to eq(true)
    expect(ClassroomMembership.exists?(assignment.id)).to eq(true)
    patch reactivate_teacher_path(member.user)
    expect(member.user.reload).to be_active
    patch deactivate_teacher_path(manager)
    expect(response).to redirect_to(root_path)
    patch deactivate_teacher_path(other_manager.user)
    expect(response).to redirect_to(root_path)
    sign_in create(:user, :admin)
    patch deactivate_teacher_path(other_manager.user)
    expect(other_manager.user.reload).to be_inactive
  end
end
