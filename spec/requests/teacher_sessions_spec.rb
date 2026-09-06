require "rails_helper"

RSpec.describe "Teacher sessions", type: :request do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  def annual_teacher(school:, school_year:, login_id: "teacher1", password: "password123", **attributes)
    teacher = create(:user, :teacher, {
      school_year:,
      login_id:,
      school_role: "member",
      password:
    }.merge(attributes))
    teacher
  end

  def login(school, login_id: "teacher1", password: "password123", ip: "203.0.113.10")
    post school_teacher_login_path(school),
      params: { teacher: { login_id:, password: } },
      headers: { "REMOTE_ADDR" => ip }
  end

  it "authenticates within the school's active year with normalized input" do
    school = create(:school)
    year = create(:school_year, :active, school:)
    teacher = annual_teacher(school:, school_year: year)

    login(school, login_id: " TEACHER1 ")

    expect(response).to redirect_to(classrooms_path)
    expect(controller.current_user).to eq(teacher)
  end

  it "rejects wrong and unknown credentials" do
    school = create(:school)
    year = create(:school_year, :active, school:)
    annual_teacher(school:, school_year: year)

    login(school, password: "wrong")
    expect(response).to have_http_status(:unprocessable_content)
    login(school, login_id: "missing")
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "isolates the same login ID between schools" do
    first_school = create(:school)
    second_school = create(:school)
    first_year = create(:school_year, :active, school: first_school)
    second_year = create(:school_year, :active, school: second_school)
    annual_teacher(school: first_school, school_year: first_year, password: "first-password")
    second = annual_teacher(school: second_school, school_year: second_year, password: "second-password")

    login(second_school, password: "second-password")

    expect(controller.current_user).to eq(second)
  end

  it "fails closed for inactive schools and missing active years" do
    inactive_school = create(:school, active: false)
    active_year = create(:school_year, :active, school: inactive_school)
    annual_teacher(school: inactive_school, school_year: active_year)
    login(inactive_school)
    expect(controller.current_user).to be_nil

    school = create(:school)
    planning_year = create(:school_year, school:)
    annual_teacher(school:, school_year: planning_year)
    login(school)
    expect(controller.current_user).to be_nil
  end

  it "does not use planning or archived accounts as fallbacks" do
    school = create(:school)
    planning = create(:school_year, school:)
    archived = create(:school_year, :archived, school:, year: 2025)
    annual_teacher(school:, school_year: planning, login_id: "planning")
    annual_teacher(school:, school_year: archived, login_id: "archived")

    login(school, login_id: "planning")
    expect(controller.current_user).to be_nil
    login(school, login_id: "archived")
    expect(controller.current_user).to be_nil
  end

  it "uses an email-shaped login ID without falling back to User.email" do
    school = create(:school)
    year = create(:school_year, :active, school:)
    teacher = annual_teacher(school:, school_year: year, login_id: "name@example.com", email: nil)

    login(school, login_id: "NAME@EXAMPLE.COM")

    expect(controller.current_user).to eq(teacher)
  end

  it "separates rate-limit attempts by school" do
    blocked_school = create(:school)
    other_school = create(:school)
    create(:school_year, :active, school: blocked_school)
    other_year = create(:school_year, :active, school: other_school)
    teacher = annual_teacher(school: other_school, school_year: other_year)

    5.times { login(blocked_school, password: "wrong") }
    login(other_school)

    expect(controller.current_user).to eq(teacher)
  end

  it "redirects temporary-password accounts to forced change" do
    school = create(:school)
    year = create(:school_year, :active, school:)
    annual_teacher(school:, school_year: year, password_change_required: true)

    login(school)

    expect(response).to redirect_to(edit_forced_password_path)
  end

  it "keeps an already signed-in forced teacher out of the login endpoint" do
    school = create(:school)
    year = create(:school_year, :active, school:)
    teacher = annual_teacher(school:, school_year: year, password_change_required: true)
    sign_in teacher

    get school_teacher_login_path(school)
    expect(response).to redirect_to(edit_forced_password_path)

    post school_teacher_login_path(school), params: {
      teacher: { login_id: "someone-else", password: "password123" }
    }
    expect(response).to redirect_to(edit_forced_password_path)
  end
end
