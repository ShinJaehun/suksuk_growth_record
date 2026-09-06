require 'rails_helper'

RSpec.describe 'Teacher operations', type: :request do
  let(:school) { create(:school) }
  let(:manager) do
    user = create(:user, :teacher, :active_annual_teacher,
                  annual_school: school,
                  annual_school_role: 'manager',
                  annual_grade: 4)
    user
  end

  def annual_teacher(school:, grade: nil)
    create(:user, :teacher, :active_annual_teacher,
           annual_school: school,
           annual_grade: grade)
  end

  it 'allows admins and managers but rejects regular teachers' do
    sign_in create(:user, :admin)
    get teachers_path
    expect(response).to have_http_status(:ok)

    sign_in manager
    get teachers_path
    expect(response).to have_http_status(:ok)

    member = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in member
    get teachers_path
    expect(response).to redirect_to(root_path)
  end

  it 'requires authentication' do
    get teachers_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'limits a manager to teachers and classrooms in their school' do
    own_teacher = annual_teacher(school: school, grade: 5)
    other_school = create(:school)
    other_teacher = annual_teacher(school: other_school)
    own_classroom = create(:classroom, annual_school: school, grade: 5)
    other_classroom = create(:classroom, annual_school: other_school, grade: 5)
    sign_in manager

    get teachers_path
    expect(response.body).to include(own_teacher.email)
    expect(response.body).not_to include(other_teacher.email)

    get edit_teacher_path(other_teacher)
    expect(response).to have_http_status(:not_found)

    get classroom_options_teachers_path,
        params: { school_id: other_school.id, membership_grade: 5 }
    expect(response.body).to include(own_classroom.class_label)
    expect(response.body).not_to include(other_classroom.class_label)
  end

  it 'limits admin listing and direct management to active SchoolYear teachers across schools' do
    admin = create(:user, :admin)
    active_teacher = annual_teacher(school: school)
    other_active_teacher = annual_teacher(school: create(:school))
    planning_year = create(:school_year, school: school, year: 2027, status: :planning)
    archived_year = create(:school_year, :archived, school: school, year: 2025)
    planning_teacher = create(:user, :teacher, school_year: planning_year,
                              school_role: 'member', login_id: 'planning-request-teacher')
    archived_teacher = create(:user, :teacher, school_year: archived_year,
                              school_role: 'member', login_id: 'archived-request-teacher')
    sign_in admin

    get teachers_path
    expect(response.body).to include(active_teacher.email, other_active_teacher.email)
    expect(response.body).not_to include(planning_teacher.email, archived_teacher.email)

    [planning_teacher, archived_teacher].each do |teacher|
      get edit_teacher_path(teacher)
      expect(response).to have_http_status(:not_found)

      patch teacher_path(teacher), params: { user: { name: '변경 불가' } }
      expect(response).to have_http_status(:not_found)

      patch deactivate_teacher_path(teacher)
      expect(response).to have_http_status(:not_found)

      patch reactivate_teacher_path(teacher)
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'filters the admin index by school' do
    other_school = create(:school)
    school_teacher = annual_teacher(school: school)
    other_teacher = annual_teacher(school: other_school)
    sign_in create(:user, :admin)

    get teachers_path, params: { school_id: school.id }

    expect(response.body).to include(school_teacher.email)
    expect(response.body).not_to include(other_teacher.email)
  end

  it 'filters teachers by active, inactive, and all status' do
    active_teacher = annual_teacher(school: school)
    inactive_teacher = annual_teacher(school: school)
    inactive_teacher.update!(active: false)
    sign_in create(:user, :admin)

    get teachers_path
    expect(response.body).to include(active_teacher.email)
    expect(response.body).not_to include(inactive_teacher.email)

    get teachers_path, params: { status: 'inactive' }
    expect(response.body).to include(inactive_teacher.email)
    expect(response.body).not_to include(active_teacher.email)

    get teachers_path, params: { status: 'all' }
    expect(response.body).to include(active_teacher.email, inactive_teacher.email)
  end

  it 'renders one grade select and one classroom select without plural assignment inputs' do
    classroom = create(:classroom, annual_school: school, grade: 5)
    sign_in manager

    get new_teacher_path, params: { membership_grade: 5 }

    document = Nokogiri::HTML(response.body)
    expect(document.css('select[name="membership_grade"]').size).to eq(1)
    expect(document.css('select[name="classroom_id"]').size).to eq(1)
    expect(document.css('input[type="checkbox"]')).to be_empty
    expect(response.body).to include(classroom.class_label)
    expect(response.body).not_to include(I18n.t('admin.teachers.form.current_classrooms'))
  end

  it 'does not query candidates until school and grade are selected' do
    admin = create(:user, :admin)
    classroom = create(:classroom, annual_school: school, grade: 5)
    sign_in admin

    get new_teacher_path
    document = Nokogiri::HTML(response.body)
    expect(
      document.at_css(%(select[name="classroom_id"] option[value="#{classroom.id}"]))
    ).to be_nil

    get new_teacher_path, params: { school_id: school.id }
    document = Nokogiri::HTML(response.body)
    expect(
      document.at_css(%(select[name="classroom_id"] option[value="#{classroom.id}"]))
    ).to be_nil

    get new_teacher_path, params: { school_id: school.id, membership_grade: 5 }
    document = Nokogiri::HTML(response.body)
    expect(
      document.at_css(%(select[name="classroom_id"] option[value="#{classroom.id}"]))
    ).to be_present
  end

  it 'creates a teacher with grade and no classroom' do
    sign_in manager
    post teachers_path, params: {
      membership_grade: 5,
      classroom_id: '',
      user: {
        name: '학급 없는 선생님',
        login_id: 'gradeonly',
        email: ''
      }
    }

    teacher = User.teacher.find_by!(login_id: 'gradeonly')
    expect(teacher).to have_attributes(
      school_year: school.school_years.active.first,
      school_role: 'member',
      grade: 5,
      email: nil,
      password_change_required: true
    )
    expect(teacher.annual_school).to eq(school)
    expect(teacher.teacher_credential_events.where(action: 'temporary_password_issued')).to exist
    expect(teacher.assigned_classroom).to be_nil
  end

  it "creates an admin-selected school's teacher in its active SchoolYear" do
    active_school_year = school.school_years.active.first || create(:school_year, :active, school: school)
    sign_in create(:user, :admin)

    post teachers_path, params: {
      school_id: school.id,
      membership_grade: 4,
      classroom_id: '',
      user: { name: '관리자 등록 교사', login_id: 'admin-created', email: '' }
    }

    expect(User.teacher.find_by!(login_id: 'admin-created')).to have_attributes(
      school_year: active_school_year,
      grade: 4,
      school_role: 'member'
    )
  end

  it 'does not create a teacher in an inactive school' do
    school.school_years.active.first || create(:school_year, :active, school: school)
    school.update!(active: false)
    sign_in create(:user, :admin)

    expect do
      post teachers_path, params: {
        school_id: school.id,
        membership_grade: 4,
        classroom_id: '',
        user: { name: '등록 금지 교사', login_id: 'inactive-school-teacher', email: '' }
      }
    end.not_to change(User.teacher, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'assigns one matching classroom and restores it on edit' do
    classroom = create(:classroom, annual_school: school, grade: 5)
    sign_in manager
    post teachers_path, params: {
      membership_grade: 5,
      classroom_id: classroom.id,
      user: {
        name: '담임 선생님',
        login_id: 'assigned',
        email: 'assigned@example.com'
      }
    }
    teacher = User.find_by!(email: 'assigned@example.com')

    expect(classroom.reload.teacher).to eq(teacher)
    get edit_teacher_path(teacher)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('select[name="membership_grade"] option[value="5"][selected]')).to be_present
    expect(document.at_css(%(select[name="classroom_id"] option[value="#{classroom.id}"][selected]))).to be_present
  end

  it 'moves and removes a single classroom assignment' do
    teacher = annual_teacher(school: school, grade: 4)
    first = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    second = create(:classroom, annual_school: school, grade: 4)
    sign_in manager

    patch teacher_path(teacher), params: {
      membership_grade: 4,
      classroom_id: second.id,
      user: { name: teacher.name, email: teacher.email }
    }
    expect(first.reload.teacher).to be_nil
    expect(second.reload.teacher).to eq(teacher)

    patch teacher_path(teacher), params: {
      membership_grade: 4,
      classroom_id: '',
      user: { name: teacher.name, email: teacher.email }
    }
    expect(second.reload.teacher).to be_nil
  end

  it 'rejects changing a persisted teacher SchoolYear without partial changes' do
    teacher = annual_teacher(school: school, grade: 4)
    classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
    other_school = create(:school)
    other_classroom = create(:classroom, annual_school: other_school, grade: 5)
    sign_in create(:user, :admin)

    patch teacher_path(teacher), params: {
      school_id: other_school.id,
      membership_grade: 5,
      classroom_id: other_classroom.id,
      user: { name: '변경 불가', email: teacher.email }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(teacher.reload).to have_attributes(
      school_year: school.school_years.active.first,
      grade: 4
    )
    expect(teacher.name).not_to eq('변경 불가')
    expect(classroom.reload.teacher).to eq(teacher)
    expect(other_classroom.reload.teacher).to be_nil
  end

  it 'shows and preserves a locked inactive classroom assignment during profile updates' do
    teacher = annual_teacher(school: school, grade: 5)
    classroom = create(:classroom, annual_school: school, grade: 5, teacher: teacher)
    classroom.update!(active: false)
    sign_in manager

    get edit_teacher_path(teacher)

    document = Nokogiri::HTML(response.body)
    expect(response.body).to include(
      I18n.t('admin.teachers.form.inactive_classroom_assignment_locked'),
      classroom.class_label
    )
    expect(document.at_css('input[name="classroom_id"]')['value']).to eq(classroom.id.to_s)
    expect(document.css('select[name="membership_grade"], select[name="classroom_id"]')).to be_empty

    patch teacher_path(teacher), params: {
      school_id: school.id,
      membership_grade: 5,
      classroom_id: classroom.id,
      user: { name: '변경된 이름', email: teacher.email }
    }

    expect(response).to redirect_to(teachers_path)
    expect(teacher.reload.name).to eq('변경된 이름')
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it 'keeps an existing inactive-school teacher manageable and allows assignment removal' do
    teacher = annual_teacher(school: school, grade: 5)
    classroom = create(:classroom, annual_school: school, grade: 5, teacher: teacher)
    school.update!(active: false)
    sign_in create(:user, :admin)

    get edit_teacher_path(teacher)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(school.name)

    patch teacher_path(teacher), params: {
      school_id: school.id,
      membership_grade: 5,
      classroom_id: '',
      user: { name: teacher.name, email: teacher.email }
    }

    expect(response).to redirect_to(teachers_path)
    expect(classroom.reload.teacher).to be_nil
    expect(teacher.reload.annual_school).to eq(school)
  end

  it 'rejects direct assignment of a different-grade or occupied classroom' do
    teacher = annual_teacher(school: school, grade: 5)
    other_teacher = annual_teacher(school: school, grade: 5)
    invalid_classrooms = [
      create(:classroom, annual_school: school, grade: 6),
      create(:classroom, annual_school: school, grade: 5, teacher: other_teacher)
    ]
    sign_in manager

    invalid_classrooms.each do |classroom|
      patch teacher_path(teacher), params: {
        membership_grade: 5,
        classroom_id: classroom.id,
        user: { name: teacher.name, email: teacher.email }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(teacher.reload.assigned_classroom).to be_nil
    end
  end

  it 'releases the classroom when a teacher is deactivated and does not restore it' do
    teacher = annual_teacher(school: school, grade: 5)
    classroom = create(:classroom, annual_school: school, grade: 5, teacher: teacher)
    sign_in manager

    patch deactivate_teacher_path(teacher)
    expect(teacher.reload).to be_inactive
    expect(classroom.reload.teacher).to be_nil

    patch reactivate_teacher_path(teacher)
    expect(teacher.reload).to be_active
    expect(classroom.reload.teacher).to be_nil
  end
end
