require 'rails_helper'

RSpec.describe 'Student PIN sessions', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:classroom) { create(:classroom) }
  let!(:student) { create(:student, classroom: classroom, student_pin: '1234') }
  let(:legacy_student) { create(:user, :student, student_pin: '1234') }
  let(:teacher) { create(:user, :teacher, :active_annual_teacher, annual_school: classroom.school_year.school) }
  let(:remote_ip) { '203.0.113.10' }

  before do
    create(:classroom_membership, classroom: classroom, user: legacy_student, role: 'student')
    assign_teacher(classroom, teacher)
  end

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  def post_student_pin(pin:, target_student: student, target_classroom: classroom, ip: remote_ip)
    post public_student_login_path(student_login_token: target_classroom.student_login_token),
         params: {
           student_id: target_student.id,
           student_pin: pin
         },
         headers: { 'REMOTE_ADDR' => ip }
  end

  def capture_request_log
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(io))
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end

  it 'does not expose all classrooms and students on the global login page' do
    other_classroom = create(:classroom, class_label: '다른 교실')
    other_student = create(:student, classroom: other_classroom, name: '다른 학생', student_pin: '5678')

    get new_student_session_path
    document = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('교실별 로그인 주소')
    expect(response.body).not_to include(student.name)
    expect(response.body).not_to include(other_student.name)
    expect(document.css('a[href^="/c/"]')).to be_empty
    expect(document.css('select[name="student_id"]')).to be_empty
  end

  it 'shows only students from the classroom login page' do
    other_classroom = create(:classroom)
    other_student = create(:student, classroom: other_classroom, name: '다른 학생', student_pin: '5678')

    get public_student_login_path(student_login_token: classroom.student_login_token)

    expected_avatar_path = ActionController::Base.helpers.asset_path('avatars/boy01.png')
    document = Nokogiri::HTML(response.body)
    student_option = document.at_css(%(option[data-student-name="#{student.name}"]))
    avatar_image = document.at_css('img[data-student-login-preview-target="image"]')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(student.name)
    expect(response.body).to include('data-controller="student-login-preview"')
    expect(response.body).to include('data-student-login-preview-target="select"')
    expect(response.body).to include('로그인할 학생을 선택하세요')
    expect(response.body).to include('<option value="">선택하세요</option>')
    expect(response.body).to include('PIN을 입력하세요')
    expect(student_option['data-avatar-url']).to eq(expected_avatar_path)
    expect(avatar_image['src']).to eq(expected_avatar_path)
    expect(response.body).not_to include('alt="선택하세요"')
    expect(response.body).to include('data-avatar-url=')
    expect(response.body).to include("data-student-name=\"#{student.name}\"")
    expect(response.body).not_to include('선택한 학생의 아바타가 여기에 표시됩니다.')
    expect(response.body).not_to include(other_student.name)
  end

  it 'does not show inactive students on the classroom login page' do
    inactive_student = create(:student, classroom: classroom, name: '비활성 학생', student_pin: '5678', active: false)

    get public_student_login_path(student_login_token: classroom.student_login_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(student.name)
    expect(response.body).not_to include(inactive_student.name)
  end

  it 'rejects planning and archived classroom login pages' do
    %w[planning archived].each do |status|
      classroom.school_year.update!(status: status)

      get public_student_login_path(student_login_token: classroom.student_login_token)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(student.name)
    end
  end

  it 'shows only students from the token classroom login page' do
    other_classroom = create(:classroom)
    other_student = create(:student, classroom: other_classroom, name: '다른 학생', student_pin: '5678')

    get public_student_login_path(student_login_token: classroom.student_login_token)

    expected_avatar_path = ActionController::Base.helpers.asset_path('avatars/boy01.png')
    document = Nokogiri::HTML(response.body)
    student_option = document.at_css(%(option[data-student-name="#{student.name}"]))
    avatar_image = document.at_css('img[data-student-login-preview-target="image"]')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(student.name)
    expect(response.body).to include(public_student_login_path(student_login_token: classroom.student_login_token))
    expect(response.body).to include('data-controller="student-login-preview"')
    expect(response.body).to include('data-student-login-preview-target="select"')
    expect(response.body).to include('로그인할 학생을 선택하세요')
    expect(response.body).to include('<option value="">선택하세요</option>')
    expect(response.body).to include('PIN을 입력하세요')
    expect(student_option['data-avatar-url']).to eq(expected_avatar_path)
    expect(avatar_image['src']).to eq(expected_avatar_path)
    expect(response.body).not_to include('alt="선택하세요"')
    expect(response.body).to include('data-avatar-url=')
    expect(response.body).to include("data-student-name=\"#{student.name}\"")
    expect(response.body).not_to include('선택한 학생의 아바타가 여기에 표시됩니다.')
    expect(response.body).not_to include(other_student.name)
  end

  it 'returns not found for an invalid student login token' do
    get public_student_login_path(student_login_token: 'invalid-token')

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include('학생 로그인 주소를 사용할 수 없습니다.')
    expect(response.body).to include('새 QR 코드나 로그인 주소')
  end

  it 'rejects GET and POST login through an inactive classroom token' do
    classroom.update!(active: false)

    get public_student_login_path(student_login_token: classroom.student_login_token)
    expect(response).to have_http_status(:not_found)

    post_student_pin(pin: '1234')
    expect(response).to have_http_status(:not_found)
    expect(controller.current_user).to be_nil
  end

  it 'filters the raw token from valid GET student login request logs' do
    token = classroom.student_login_token

    logs = capture_request_log do
      get public_student_login_path(student_login_token: token)
    end

    expect(response).to have_http_status(:ok)
    expect(logs).to include('/c/[FILTERED]/login')
    expect(logs).not_to include(token)
  end

  it 'filters the raw token and PIN from POST student login request logs' do
    token = classroom.student_login_token

    logs = capture_request_log do
      post public_student_login_path(student_login_token: token), params: {
        student_id: student.id,
        student_pin: '1234'
      }
    end

    expect(response).to redirect_to(student_profile_path)
    expect(logs).to include('/c/[FILTERED]/login')
    expect(logs).not_to include(token)
    expect(logs).not_to include('1234')
    expect(logs).to include('[FILTERED]')
  end

  it 'filters an invalid raw token from request logs' do
    invalid_token = 'invalid-student-login-token'

    logs = capture_request_log do
      get public_student_login_path(student_login_token: invalid_token)
    end

    expect(response).to have_http_status(:not_found)
    expect(logs).to include('/c/[FILTERED]/login')
    expect(logs).not_to include(invalid_token)
  end

  it 'does not mask ordinary request paths' do
    logs = capture_request_log do
      get new_student_session_path
    end

    expect(response).to have_http_status(:ok)
    expect(logs).to include('/student_login')
    expect(logs).not_to include('/c/[FILTERED]/login')
  end

  it 'does not route a numeric classroom login URL' do
    expect do
      Rails.application.routes.recognize_path(
        "/classrooms/#{classroom.id}/student_login",
        method: :get
      )
    end.to raise_error(ActionController::RoutingError)
  end

  it 'does not route a numeric login URL for another classroom' do
    other_classroom = create(:classroom)

    expect do
      Rails.application.routes.recognize_path(
        "/classrooms/#{other_classroom.id}/student_login",
        method: :post
      )
    end.to raise_error(ActionController::RoutingError)
  end

  it 'does not treat a numeric classroom id as a student login token' do
    get public_student_login_path(student_login_token: classroom.id)

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include('학생 로그인 주소를 사용할 수 없습니다.')
    expect(response.body).not_to include(student.name)
  end

  it 'signs in a student with classroom, student, and PIN' do
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: '1234'
    }

    expect(response).to redirect_to(student_profile_path)
    expect(session[:student_id]).to eq(student.id)
  end

  it 'signs in a student through the token classroom login route' do
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: '1234'
    }

    expect(response).to redirect_to(student_profile_path)
    expect(session[:student_id]).to eq(student.id)
    expect(session[:student_login_classroom_id]).to eq(classroom.id)
  end

  it 'stores the student session last seen timestamp after PIN login' do
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: '1234'
    }

    expect(session[:student_login_classroom_id]).to eq(classroom.id)
    expect(session[:student_last_seen_at]).to be_present
    expect(controller.current_user).to be_nil
  end

  it 'clears an existing Devise User session when Student login succeeds' do
    sign_in teacher

    post_student_pin(pin: '1234')

    expect(controller.current_user).to be_nil
    expect(session[:student_id]).to eq(student.id)
  end

  it 'keeps a student signed in within the TTL and refreshes last seen' do
    travel_to Time.zone.local(2026, 5, 22, 10, 0, 0) do
      post public_student_login_path(student_login_token: classroom.student_login_token), params: {
        student_id: student.id,
        student_pin: '1234'
      }
    end

    travel_to Time.zone.local(2026, 5, 22, 10, 5, 0) do
      get student_profile_path
    end

    expect(response).to have_http_status(:ok)
    expect(session[:student_last_seen_at]).to eq(Time.zone.local(2026, 5, 22, 10, 5, 0).to_i)
  end

  it 'ends an existing student session after the classroom is deactivated' do
    post_student_pin(pin: '1234')
    classroom.update!(active: false)

    get student_profile_path

    expect(response).to redirect_to(public_student_login_path(student_login_token: classroom.student_login_token))
    expect(controller.current_user).to be_nil
  end

  it 'ends an existing Student session when the SchoolYear is no longer active' do
    post_student_pin(pin: '1234')
    classroom.school_year.update_columns(status: 'archived')

    get student_profile_path

    expect(response).to redirect_to(public_student_login_path(student_login_token: classroom.student_login_token))
    expect(session[:student_id]).to be_nil
  end

  it 'ends an existing Student session when the SchoolYear is planning' do
    post_student_pin(pin: '1234')
    classroom.school_year.update_columns(status: 'planning')

    get student_profile_path

    expect(response).to redirect_to(public_student_login_path(student_login_token: classroom.student_login_token))
    expect(session[:student_id]).to be_nil
  end

  it 'ends an existing Student session when the School is inactive' do
    post_student_pin(pin: '1234')
    classroom.school_year.school.update!(active: false)

    get student_profile_path

    expect(response).to redirect_to(public_student_login_path(student_login_token: classroom.student_login_token))
    expect(session[:student_id]).to be_nil
  end

  it 'redirects an expired student session to the classroom PIN login page' do
    travel_to Time.zone.local(2026, 5, 22, 10, 0, 0) do
      post public_student_login_path(student_login_token: classroom.student_login_token), params: {
        student_id: student.id,
        student_pin: '1234'
      }
    end

    travel_to Time.zone.local(2026, 5, 22, 10, 21, 1) do
      get student_profile_path
    end

    expect(response).to redirect_to(public_student_login_path(student_login_token: classroom.student_login_token))
    expect(controller.current_user).to be_nil
  end

  it 'initializes missing student last seen without expiring the session' do
    post_student_pin(pin: '1234')
    session.delete(:student_last_seen_at)

    get student_profile_path

    expect(response).to have_http_status(:ok)
    expect(session[:student_last_seen_at]).to be_present
  end

  it 'redirects student logout back to the classroom PIN login page' do
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: '1234'
    }

    expect(session[:student_login_classroom_id]).to eq(classroom.id)

    delete destroy_student_session_path

    expect(response).to redirect_to(public_student_login_path(student_login_token: classroom.student_login_token))
  end

  it 'falls back to the global student login page without a stored classroom' do
    delete destroy_student_session_path

    expect(response).to redirect_to(new_student_session_path)
  end

  it 'shows a student-specific logout link on the self page' do
    post_student_pin(pin: '1234')

    get student_profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('사용 끝내기')
    expect(response.body).to include(destroy_student_session_path)
    expect(response.body).not_to include(destroy_user_session_path)
  end

  it 'does not apply student TTL to a teacher' do
    sign_in teacher

    get classrooms_path

    expect(response).to redirect_to(classroom_path(classroom))
    expect(controller.current_user).to eq(teacher)
  end

  it 'rejects an invalid PIN' do
    post_student_pin(pin: '0000')

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('학생 PIN 로그인')
  end

  it 'keeps the existing failure response for the first four failed PIN attempts' do
    4.times do
      post_student_pin(pin: '0000')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('교실, 학생, PIN을 확인해 주세요.')
      expect(response.body).not_to include('로그인 시도가 너무 많습니다.')
    end
  end

  it 'blocks the same student, classroom, and IP after five failed PIN attempts' do
    4.times { post_student_pin(pin: '0000') }

    post_student_pin(pin: '0000')

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('로그인 시도가 너무 많습니다. 잠시 후 다시 시도해 주세요.')
    expect(response.body).to include(student.name)

    post_student_pin(pin: '1234')

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('로그인 시도가 너무 많습니다. 잠시 후 다시 시도해 주세요.')
    expect(response.body).to include(student.name)
    expect(controller.current_user).to be_nil
  end

  it 'allows login again after the throttle window expires' do
    travel_to Time.zone.local(2026, 5, 22, 10, 0, 0) do
      5.times { post_student_pin(pin: '0000') }
    end

    travel_to Time.zone.local(2026, 5, 22, 10, 10, 1) do
      post_student_pin(pin: '1234')
    end

    expect(response).to redirect_to(student_profile_path)
  end

  it 'resets failed attempts after a successful PIN login before throttling' do
    4.times { post_student_pin(pin: '0000') }
    post_student_pin(pin: '1234')
    delete destroy_student_session_path

    4.times { post_student_pin(pin: '0000') }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('교실, 학생, PIN을 확인해 주세요.')
    expect(response.body).not_to include('로그인 시도가 너무 많습니다.')
  end

  it 'does not throttle a different student on the same IP' do
    other_student = create(:student, classroom: classroom, student_pin: '5678')
    5.times { post_student_pin(pin: '0000') }

    post_student_pin(pin: '5678', target_student: other_student)

    expect(response).to redirect_to(student_profile_path)
  end

  it 'does not throttle a different classroom on the same IP' do
    other_classroom = create(:classroom)
    other_student = create(:student, classroom: other_classroom, student_pin: '5678')
    5.times { post_student_pin(pin: '0000') }

    post_student_pin(pin: '5678', target_student: other_student, target_classroom: other_classroom)

    expect(response).to redirect_to(student_profile_path)
  end

  it 'does not throttle the same student from a different IP' do
    5.times { post_student_pin(pin: '0000') }

    post_student_pin(pin: '1234', ip: '203.0.113.11')

    expect(response).to redirect_to(student_profile_path)
  end

  it 'keeps invalid token handling outside PIN throttling' do
    get public_student_login_path(student_login_token: 'invalid-token')

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include('학생 로그인 주소를 사용할 수 없습니다.')
  end

  it 'does not affect school-scoped teacher login' do
    5.times { post_student_pin(pin: '0000') }

    post school_teacher_login_path(classroom.school_year.school), params: {
      teacher: {
        login_id: teacher.login_id,
        password: 'password123'
      }
    }

    expect(response).to redirect_to(classroom_path(classroom))
    expect(controller.current_user).to eq(teacher)
  end

  it 'rejects an inactive student with a valid PIN' do
    student.update!(active: false)

    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: '1234'
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('교실, 학생, PIN을 확인해 주세요.')
    expect(controller.current_user).to be_nil
  end

  it 'signs out a Student who becomes inactive after PIN login' do
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: '1234'
    }
    student.update!(active: false)

    get student_profile_path

    expect(response).to redirect_to(public_student_login_path(student_login_token: classroom.student_login_token))
    expect(controller.current_user).to be_nil
  end

  it 'rejects a student outside the classroom' do
    other_classroom = create(:classroom)
    other_student = create(:student, classroom: other_classroom, student_pin: '5678')

    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: other_student.id,
      student_pin: '5678'
    }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'renders the Student management PIN field without exposing its digest' do
    sign_in teacher

    get edit_classroom_student_path(classroom, student)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('type="password"')
    expect(response.body).to include('name="student[student_pin]"')
    expect(response.body).to include('새 PIN을 입력하면 변경됩니다. 비워두면 기존 PIN을 유지합니다.')
    expect(response.body).not_to include(student.student_pin_digest)
  end

  it 'uses a teacher-managed Student PIN for the actual Student login' do
    sign_in teacher

    patch classroom_student_path(classroom, student), params: { student: { student_pin: '4321' } }
    sign_out teacher

    post_student_pin(pin: '1234')
    expect(response).to have_http_status(:unprocessable_content)
    post_student_pin(pin: '4321')
    expect(response).to redirect_to(student_profile_path)
  end
end
