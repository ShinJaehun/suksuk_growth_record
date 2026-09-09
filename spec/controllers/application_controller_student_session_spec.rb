require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  include Devise::Test::ControllerHelpers

  controller do
    def index
      render json: {
        student_id: current_student&.id,
        student_signed_in: student_signed_in?,
        actor_type: pundit_user&.class&.name,
        actor_id: pundit_user&.id
      }
    end

    private

    def skip_pundit_verify_authorized?
      true
    end

    def pundit_verify_policy_scoped?
      false
    end
  end

  before do
    routes.draw { get 'index' => 'anonymous#index' }
  end

  def response_body
    JSON.parse(response.body)
  end

  def set_student_session(student, classroom_id: student.classroom_id)
    session[:student_id] = student.id
    session[:student_login_classroom_id] = classroom_id
  end

  def expect_student_session_rejected
    expect(response).to redirect_to(new_student_session_path)
    expect(session[:student_id]).to be_nil
    expect(session[:student_login_classroom_id]).to be_nil
    expect(session[:student_last_seen_at]).to be_nil
  end

  it 'has no current Student without a student session' do
    get :index

    expect(response_body).to include(
      'student_id' => nil,
      'student_signed_in' => false,
      'actor_type' => nil
    )
  end

  it 'resolves an eligible Student in the session classroom' do
    student = create(:student)
    set_student_session(student)

    get :index

    expect(response_body).to include(
      'student_id' => student.id,
      'student_signed_in' => true,
      'actor_type' => 'Student',
      'actor_id' => student.id
    )
  end

  it 'rejects an inactive Student' do
    student = create(:student, active: false)
    set_student_session(student)

    get :index

    expect_student_session_rejected
  end

  it 'rejects an inactive Classroom' do
    student = create(:student)
    student.classroom.update!(active: false)
    set_student_session(student)

    get :index

    expect_student_session_rejected
  end

  it 'rejects a planning SchoolYear' do
    student = create(:student)
    student.classroom.school_year.update_columns(status: 'planning')
    set_student_session(student)

    get :index

    expect_student_session_rejected
  end

  it 'rejects an archived SchoolYear' do
    student = create(:student)
    student.classroom.school_year.update_columns(status: 'archived')
    set_student_session(student)

    get :index

    expect_student_session_rejected
  end

  it 'rejects an inactive School' do
    student = create(:student)
    student.classroom.school_year.school.update!(active: false)
    set_student_session(student)

    get :index

    expect_student_session_rejected
  end

  it 'rejects a mismatched session Classroom' do
    student = create(:student)
    other_classroom = create(:classroom)
    set_student_session(student, classroom_id: other_classroom.id)

    get :index

    expect_student_session_rejected
  end

  it 'rejects a Student session without a stored Classroom' do
    student = create(:student)
    session[:student_id] = student.id

    get :index

    expect(response).to redirect_to(new_student_session_path)
    expect(session[:student_id]).to be_nil
  end

  it 'uses the Devise User as the Pundit actor when both contexts exist' do
    student = create(:student)
    admin = create(:user, :admin)
    set_student_session(student)
    sign_in admin

    get :index

    expect(response_body).to include('actor_type' => 'User', 'actor_id' => admin.id)
  end
end
