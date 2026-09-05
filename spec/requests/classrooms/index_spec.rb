require "rails_helper"

RSpec.describe "Classrooms index entry", type: :request do
  it "redirects an ordinary teacher to their active assigned classroom" do
    membership = create(:school_membership, grade: 4)
    classroom = create(:classroom, school: membership.school, grade: 4)
    assign_teacher(classroom, membership.user)
    sign_in membership.user

    get classrooms_path

    expect(response).to redirect_to(classroom_path(classroom))
  end

  it "shows the empty index for an ordinary teacher without an assignment" do
    membership = create(:school_membership)
    sign_in membership.user

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("classrooms.index.empty"))
  end

  it "does not redirect an ordinary teacher to an inactive assigned classroom" do
    membership = create(:school_membership, grade: 4)
    classroom = create(:classroom, school: membership.school, grade: 4, teacher: membership.user)
    classroom.update!(active: false)
    sign_in membership.user

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(classroom_path(classroom))
  end

  it "does not redirect an ordinary teacher to a classroom in an inactive school" do
    membership = create(:school_membership, grade: 4)
    classroom = create(:classroom, school: membership.school, grade: 4, teacher: membership.user)
    membership.school.update!(active: false)
    sign_in membership.user

    get classrooms_path

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(classroom_path(classroom))
  end

  it "keeps the classrooms index for a school manager" do
    membership = create(:school_membership, :manager, grade: 4)
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
