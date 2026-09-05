require 'rails_helper'

RSpec.describe 'Admin teacher school and classroom assignments', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let(:other_school) { create(:school) }

  def teacher_params(email: 'teacher@example.com')
    { name: '교사', email: email, password: 'password123', gender: 'female', avatar_key: 'teacherF01' }
  end

  it 'creates a teacher with school, grade, and one classroom' do
    classroom = create(:classroom, school: school, grade: 4)
    sign_in admin

    post admin_teachers_path, params: {
      user: teacher_params,
      school_id: school.id,
      membership_grade: 4,
      classroom_id: classroom.id
    }

    teacher = User.find_by!(email: 'teacher@example.com')
    expect(response).to redirect_to(admin_teachers_path)
    expect(teacher.school_membership).to have_attributes(school: school, grade: 4, role: 'member')
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
    expect(teacher.school_membership).to have_attributes(school: school, grade: 4)
    expect(teacher.assigned_classroom).to be_nil
  end

  it 'moves and removes a single classroom assignment' do
    membership = create(:school_membership, :manager, school: school, grade: 4)
    first = create(:classroom, school: school, grade: 4, teacher: membership.user)
    second = create(:classroom, school: school, grade: 4)
    sign_in admin

    patch admin_teacher_path(membership.user), params: {
      school_id: school.id, membership_grade: 4, classroom_id: second.id
    }

    expect(first.reload.teacher).to be_nil
    expect(second.reload.teacher).to eq(membership.user)
    expect(membership.reload).to be_manager

    patch admin_teacher_path(membership.user), params: {
      school_id: school.id, membership_grade: 4, classroom_id: ''
    }
    expect(second.reload.teacher).to be_nil
  end

  it 'changes school atomically and demotes a manager to member' do
    membership = create(:school_membership, :manager, school: school, grade: 4)
    old_classroom = create(:classroom, school: school, grade: 4, teacher: membership.user)
    new_classroom = create(:classroom, school: other_school, grade: 5)
    sign_in admin

    patch admin_teacher_path(membership.user), params: {
      school_id: other_school.id, membership_grade: 5, classroom_id: new_classroom.id
    }

    expect(response).to redirect_to(edit_admin_teacher_path(membership.user))
    expect(membership.reload).to have_attributes(school: other_school, grade: 5, role: 'member')
    expect(old_classroom.reload.teacher).to be_nil
    expect(new_classroom.reload.teacher).to eq(membership.user)
  end

  it 'rejects invalid classroom choices without partial changes' do
    membership = create(:school_membership, school: school, grade: 4)
    classroom = create(:classroom, school: school, grade: 4, teacher: membership.user)
    sign_in admin

    patch admin_teacher_path(membership.user), params: {
      school_id: school.id,
      membership_grade: 4,
      classroom_id: create(:classroom, school: other_school, grade: 4).id
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(membership.reload.school).to eq(school)
    expect(classroom.reload.teacher).to eq(membership.user)
  end

  it 'removes school membership and assignment when school is blank' do
    membership = create(:school_membership, school: school, grade: 4)
    classroom = create(:classroom, school: school, grade: 4, teacher: membership.user)
    sign_in admin

    patch admin_teacher_path(membership.user), params: {
      school_id: '', membership_grade: '', classroom_id: ''
    }

    expect(membership.user.reload.school_membership).to be_nil
    expect(classroom.reload.teacher).to be_nil
  end
end
