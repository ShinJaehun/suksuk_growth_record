require "rails_helper"

RSpec.describe "Admin school managers", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let(:teacher) do
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: 4)
  end

  it "designates the annual teacher role without creating a legacy membership" do
    annual_teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: annual_teacher.id }

    expect(response).to redirect_to(edit_school_path(school))
    expect(annual_teacher.reload.school_role).to eq("manager")
    expect(annual_teacher.school_membership).to be_nil
  end

  it "promotes an existing school member without changing assignments" do
    membership = create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, grade: 4)
    assign_teacher(classroom, teacher)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_manager
    expect(membership.reload).to be_member
    expect(classroom.reload.teacher).to eq(teacher)
    expect(teacher.reload.school_membership).to eq(membership)
  end

  it "rejects promoting an inactive school member without changing managers" do
    existing_manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
    inactive_membership = create(
      :school_membership,
      school: school,
      user: create(:user, :teacher, :active_annual_teacher, annual_school: school, active: false)
    )
    sign_in admin

    expect do
      post admin_school_school_managers_path(school),
        params: { user_id: inactive_membership.user_id }
    end.not_to change { school.school_years.active.first.users.where(school_role: "manager").count }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(flash[:alert]).to include(I18n.t("school_memberships.errors.inactive_manager"))
    expect(inactive_membership.user.reload).to be_school_member
    expect(existing_manager.reload).to be_school_manager
  end

  it "demotes a manager without deleting membership or assignments" do
    membership = create(:school_membership, :manager, school: school, user: teacher)
    teacher.update!(school_role: "manager")
    classroom = create(:classroom, school: school, grade: 4)
    assign_teacher(classroom, teacher)
    sign_in admin

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_member
    expect(membership.reload).to be_manager
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it "rejects a second manager and keeps the existing manager" do
    existing_manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
    existing_membership = create(:school_membership, :manager, school: school, user: existing_manager)
    membership = create(:school_membership, school: school, user: teacher)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(existing_manager.reload).to be_school_manager
    expect(existing_membership.reload).to be_manager
    expect(teacher.reload).to be_school_member
    expect(membership.reload).to be_member
    expect(school.school_years.active.first.users.where(school_role: "manager").count).to eq(1)
  end

  it "returns to school settings after a Turbo manager change" do
    membership = create(:school_membership, school: school, user: teacher)
    sign_in admin

    post admin_school_school_managers_path(school),
      params: { user_id: teacher.id },
      headers: { "Accept" => Mime[:turbo_stream].to_s }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_manager
    expect(membership.reload).to be_member
  end

  it "rejects a school manager actor" do
    actor = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager")
    create(:school_membership, :manager, school: school, user: actor)
    sign_in actor

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(root_path)
    expect(teacher.reload.school_membership).to be_nil
  end

  it "rejects a school member actor" do
    actor = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    create(:school_membership, school: school, user: actor)
    sign_in actor

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(root_path)
    expect(teacher.reload.school_membership).to be_nil
  end

  it "rejects a school manager actor demoting a manager" do
    membership = create(:school_membership, :manager, school: school, user: teacher)
    actor_school = create(:school)
    actor = create(:user, :teacher, :active_annual_teacher,
      annual_school: actor_school,
      annual_school_role: "manager")
    create(:school_membership, :manager, school: actor_school, user: actor)
    sign_in actor

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(root_path)
    expect(membership.reload).to be_manager
  end

  it "rejects a school member actor demoting a manager" do
    membership = create(:school_membership, :manager, school: school, user: teacher)
    actor = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    create(:school_membership, school: school, user: actor)
    sign_in actor

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(root_path)
    expect(membership.reload).to be_manager
  end

  it "rejects a student target" do
    target = create(:user, :student)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
    expect(target.reload.school_membership).to be_nil
  end

  it "rejects an unassigned teacher target" do
    target = create(:user, :teacher)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
    expect(target.reload.school_membership).to be_nil
  end

  it "rejects an other-school teacher target without changing its membership" do
    other_school = create(:school)
    other_teacher = create(:user, :teacher, :active_annual_teacher, annual_school: other_school)
    membership = create(
      :school_membership,
      school: other_school,
      user: other_teacher,
      role: :member
    )
    original_school_id = membership.school_id
    target = membership.user
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
    expect(target.reload.school_membership).to eq(membership)
    expect(membership.reload).to have_attributes(
      school_id: original_school_id,
      role: "member"
    )
  end
end
