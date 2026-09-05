require "rails_helper"

RSpec.describe "Classroom teacher assignment boundary", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let(:teacher) do
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: 4)
  end

  it "does not expose teacher assignment inputs on classroom forms" do
    classroom = create(:classroom, school: school)
    sign_in admin

    get edit_classroom_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('name="classroom[teacher_id]"')
    expect(response.body).not_to include('name="classroom[teacher_ids][]"')
  end

  it "ignores a forged teacher assignment while updating a classroom" do
    classroom = create(:classroom, school: school, grade: 4, teacher: teacher)
    other_teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: 4)
    sign_in admin

    patch classroom_path(classroom), params: {
      classroom: { name: "변경 학급", grade: 4, teacher_id: other_teacher.id }
    }

    expect(response).to redirect_to(classroom_path(classroom))
    expect(classroom.reload.teacher).to eq(teacher)
  end
end
