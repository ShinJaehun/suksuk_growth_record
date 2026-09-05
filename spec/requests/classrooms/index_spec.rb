require "rails_helper"

RSpec.describe "Classrooms index entry", type: :request do
  it "redirects an ordinary teacher to their active assigned classroom" do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school, annual_grade: 4)
    membership = create(:school_membership, school: school, user: teacher, grade: 4)
    classroom = create(:classroom, school: membership.school, grade: 4)
    assign_teacher(classroom, membership.user)
    sign_in membership.user

    get classrooms_path

    expect(response).to redirect_to(classroom_path(classroom))
  end

  it "shows the empty index for an ordinary teacher without an assignment" do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    membership = create(:school_membership, school: school, user: teacher)
    sign_in membership.user

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("classrooms.index.empty"))
  end

  it "does not redirect an ordinary teacher to an inactive assigned classroom" do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school, annual_grade: 4)
    membership = create(:school_membership, school: school, user: teacher, grade: 4)
    classroom = create(:classroom, school: membership.school, grade: 4, teacher: membership.user)
    classroom.update!(active: false)
    sign_in membership.user

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(classroom_path(classroom))
  end

  it "expires an ordinary teacher session when their school becomes inactive" do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school, annual_grade: 4)
    membership = create(:school_membership, school: school, user: teacher, grade: 4)
    classroom = create(:classroom, school: membership.school, grade: 4, teacher: membership.user)
    sign_in membership.user
    membership.school.update!(active: false)

    get classrooms_path

    expect(response).to redirect_to(school_teacher_login_path(school))
  end

  it "keeps the classrooms index for a school manager" do
    school = create(:school)
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager",
      annual_grade: 4)
    membership = create(:school_membership, :manager, school: school, user: manager, grade: 4)
    classroom = create(:classroom, school: membership.school, grade: 4, teacher: membership.user)
    sign_in membership.user

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(classroom_path(classroom))
  end

  it "keeps the classrooms index for an admin" do
    classroom = create(:classroom)
    sign_in create(:user, :admin)

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(classroom_path(classroom))
  end
end
