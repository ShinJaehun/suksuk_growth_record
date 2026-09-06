require 'rails_helper'

RSpec.describe 'Home', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:student) { create(:user, :student) }
  let(:classroom) { create(:classroom) }
  let(:teacher) { create(:user, :teacher, :active_annual_teacher, annual_school: classroom.school_year.school) }

  it 'redirects guests to the teacher and admin sign in page' do
    get root_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'redirects a signed-in teacher with no assigned classrooms to classrooms index' do
    sign_in teacher

    get root_path

    expect(response).to redirect_to(classrooms_path)
  end

  it 'redirects a signed-in teacher with one assigned classroom to that classroom' do
    assign_teacher(classroom, teacher)
    sign_in teacher

    get root_path

    expect(response).to redirect_to(classroom_path(classroom))
  end

  it 'redirects a signed-in admin to schools index' do
    sign_in admin

    get root_path

    expect(response).to redirect_to(schools_path)
  end

  it 'sends a signed-in student through the existing canonical student redirect flow' do
    create(:classroom_membership, classroom: classroom, user: student, role: 'student')
    sign_in student

    get root_path

    expect(response).to redirect_to(user_path(student))
  end

  it 'labels the Devise sign in page as admin login' do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t('users.sessions.admin_title'))
  end
end
