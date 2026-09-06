require "rails_helper"

RSpec.describe "Role landing pages", type: :request do
  it "redirects the admin namespace root to schools" do
    get admin_root_path

    expect(response).to redirect_to("/schools")
  end

  it "routes an admin to schools" do
    sign_in create(:user, :admin)
    get root_path
    expect(response).to redirect_to(schools_path)
  end

  it "routes a single-school manager to the school page" do
    school = create(:school)
    manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
    sign_in manager
    get root_path
    expect(response).to redirect_to(school_path(school))
  end

  it "routes a regular teacher without assigned classrooms to classrooms" do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in teacher
    get root_path
    expect(response).to redirect_to(classrooms_path)
  end

  it "routes a regular teacher with one assigned classroom to that classroom" do
    school = create(:school)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    classroom = create(:classroom, annual_school: school)
    assign_teacher(classroom, teacher)
    sign_in teacher

    get root_path

    expect(response).to redirect_to(classroom_path(classroom))
  end

  it "expires a legacy student User session before landing" do
    student = create(:user, :student)
    sign_in student

    get root_path

    expect(response).to redirect_to(new_user_session_path)
    expect(controller.current_user).to be_nil
  end
end
