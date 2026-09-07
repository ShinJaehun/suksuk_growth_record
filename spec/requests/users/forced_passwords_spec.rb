require "rails_helper"

RSpec.describe "Forced teacher password change", type: :request do
  let(:school) { create(:school) }
  let(:school_year) { create(:school_year, :active, school:) }
  let(:teacher) do
    create(:user, :teacher,
      school_year:,
      login_id: "teacher1",
      school_role: "member",
      password_change_required: true)
  end

  def login_teacher(password: "password123")
    post school_teacher_login_path(school), params: {
      teacher: { login_id: teacher.login_id, password: password }
    }
  end

  it "blocks normal application access but allows sign out" do
    login_teacher

    get classrooms_path
    expect(response).to redirect_to(edit_forced_password_path)

    delete destroy_user_session_path
    expect(controller.current_user).to be_nil
  end

  it "changes the password, clears forced state, and rotates the session" do
    login_teacher
    expect(response).to redirect_to(edit_forced_password_path)

    patch forced_password_path, params: {
      user: { password: "new-password123", password_confirmation: "new-password123" }
    }

    expect(response).to redirect_to(classrooms_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(controller.current_user).to eq(teacher)
    expect(teacher.reload).not_to be_password_change_required
    expect(teacher.valid_password?("new-password123")).to be(true)

    delete destroy_user_session_path
    login_teacher
    expect(controller.current_user).to be_nil
    login_teacher(password: "new-password123")
    expect(controller.current_user).to eq(teacher)
  end

  it "expires an existing session when annual runtime eligibility is lost" do
    teacher.update!(password_change_required: false)
    login_teacher
    school_year.update!(status: :archived)

    get classrooms_path

    expect(response).to redirect_to(school_teacher_login_path(school))
    expect(controller.current_user).to be_nil
  end

  it "loses normal authority through Devise when the annual teacher becomes inactive" do
    teacher.update!(password_change_required: false)
    login_teacher
    teacher.update!(active: false)

    get classrooms_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "fails closed when the annual school becomes inactive" do
    teacher.update!(password_change_required: false)
    login_teacher
    school.update!(active: false)

    get classrooms_path

    expect(response).to redirect_to(school_teacher_login_path(school))
    expect(controller.current_user).to be_nil
  end

  it "allows an eligible active teacher to reach the existing application" do
    teacher.update!(password_change_required: false)
    login_teacher

    get classrooms_path

    expect(response).to have_http_status(:ok)
  end

  it "does not let a session survive credential reissue" do
    teacher.update!(password_change_required: false)
    login_teacher
    get classrooms_path
    expect(response).to have_http_status(:ok)

    credential = AnnualTeacherUsers::TemporaryCredential.call(
      teacher:,
      actor: create(:user, :admin),
      action: :temporary_password_reissued
    )

    get classrooms_path

    expect(response).to redirect_to(new_user_session_path)
    expect(response).not_to have_http_status(:ok)

    login_teacher(password: credential.temporary_password)
    expect(response).to redirect_to(edit_forced_password_path)
  end

  it "keeps the forced flag and old credential after invalid password submissions" do
    login_teacher
    old_digest = teacher.encrypted_password

    [
      { password: "", password_confirmation: "" },
      { password: "new-password123", password_confirmation: "different" },
      { password: "short", password_confirmation: "short" }
    ].each do |attributes|
      patch forced_password_path, params: { user: attributes }

      expect(response).to have_http_status(:unprocessable_content)
      expect(teacher.reload).to be_password_change_required
      expect(teacher.encrypted_password).to eq(old_digest)
    end
  end
end
