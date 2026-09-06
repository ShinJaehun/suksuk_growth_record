require "rails_helper"

RSpec.describe "Student self service", type: :request do
  let(:classroom) { create(:classroom) }
  let(:student) { create(:student, classroom: classroom, name: "김학생", student_number: 7, student_pin: "1234") }

  def sign_in_student
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: "1234"
    }
  end

  it "rejects access without a Student session" do
    get student_profile_path

    expect(response).to redirect_to(new_student_session_path)
  end

  it "shows only the current Student profile data" do
    other_student = create(:student, classroom: classroom, name: "다른 학생", student_pin: "5678")
    sign_in_student

    get student_profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(student.name, "7번", classroom.class_label)
    expect(response.body).not_to include(other_student.name)
  end

  it "shows self-service PIN fields without teacher management fields" do
    sign_in_student

    get edit_student_pin_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="student[student_pin]"')
    expect(response.body).to include('name="student[student_pin_confirmation]"')
    expect(response.body).not_to include('name="student[name]"')
    expect(response.body).not_to include('name="student[avatar_key]"')
    expect(response.body).not_to include('name="student[student_number]"')
  end

  it "shows an unassigned student number without an editable number field" do
    student.update!(student_number: nil)
    sign_in_student

    get student_profile_path

    expect(response.body).to include("미지정")
    expect(response.body).not_to include('name="student[student_number]"')
  end

  it "updates the current Student PIN" do
    sign_in_student

    patch student_pin_path, params: {
      student: { student_pin: "4321", student_pin_confirmation: "4321" }
    }

    expect(response).to redirect_to(student_profile_path)
    expect(student.reload.authenticate_student_pin("4321")).to be_truthy
    expect(student.authenticate_student_pin("1234")).to be_falsey
  end

  it "ignores teacher-managed fields submitted to the self-service PIN endpoint" do
    original_attributes = student.attributes.slice("name", "student_number", "avatar_key", "active")
    sign_in_student

    patch student_pin_path, params: {
      student: {
        student_pin: "4321",
        student_pin_confirmation: "4321",
        name: "변조 이름",
        student_number: 99,
        avatar_key: "girl01",
        active: false
      }
    }

    expect(student.reload.attributes.slice("name", "student_number", "avatar_key", "active")).to eq(original_attributes)
    expect(student.authenticate_student_pin("4321")).to be_truthy
  end

  it "rejects blank, invalid, and mismatched PIN values" do
    sign_in_student

    [["", ""], ["12ab", "12ab"], ["4321", "1234"]].each do |pin, confirmation|
      patch student_pin_path, params: {
        student: { student_pin: pin, student_pin_confirmation: confirmation }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(student.reload.authenticate_student_pin("1234")).to be_truthy
    end
  end

  it "does not update another Student when changing its own PIN" do
    other_student = create(:student, classroom: classroom, student_pin: "5678")
    original_digest = other_student.student_pin_digest
    sign_in_student

    patch student_pin_path, params: {
      student: { student_pin: "4321", student_pin_confirmation: "4321" }
    }

    expect(other_student.reload.student_pin_digest).to eq(original_digest)
  end
end
