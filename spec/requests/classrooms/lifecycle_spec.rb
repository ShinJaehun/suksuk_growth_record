require "rails_helper"

RSpec.describe "Classroom lifecycle", type: :request do
  let(:school) { create(:school) }
  let(:admin) { create(:user, :admin) }

  it "lets an admin deactivate while preserving students and the teacher" do
    teacher_membership = create(:school_membership, school: school, grade: 4)
    classroom = create(:classroom, school: school, grade: 4, teacher: teacher_membership.user)
    student_membership = create(:classroom_membership, classroom: classroom, role: :student,
                                                       status: :active, student_number: 7)
    sign_in admin

    patch deactivate_classroom_path(classroom)

    expect(response).to redirect_to(classrooms_path)
    expect(classroom.reload).not_to be_active
    expect(classroom.teacher).to eq(teacher_membership.user)
    expect(student_membership.reload).to have_attributes(status: "active", student_number: 7)
  end

  it "lets an own-school manager deactivate a classroom" do
    manager = create(:school_membership, :manager, school: school).user
    classroom = create(:classroom, school: school)
    sign_in manager

    patch deactivate_classroom_path(classroom)

    expect(response).to redirect_to(classrooms_path)
    expect(classroom.reload).not_to be_active
  end

  it "reactivates with the preserved teacher assignment" do
    teacher_membership = create(:school_membership, school: school, grade: 4)
    classroom = create(:classroom, school: school, grade: 4, teacher: teacher_membership.user)
    classroom.update!(active: false)
    sign_in admin

    patch reactivate_classroom_path(classroom)

    expect(response).to redirect_to(classrooms_path)
    expect(classroom.reload).to be_active
    expect(classroom.teacher).to eq(teacher_membership.user)
  end

  it "rejects an ordinary teacher" do
    teacher = create(:user, :teacher)
    classroom = create(:classroom, school: school)
    assign_teacher(classroom, teacher)
    sign_in teacher

    patch deactivate_classroom_path(classroom)

    expect(response).to redirect_to(root_path)
    expect(classroom.reload).to be_active
  end

  it "keeps another-school manager outside the classroom scope" do
    manager = create(:school_membership, :manager, school: create(:school)).user
    classroom = create(:classroom, school: school)
    sign_in manager

    patch deactivate_classroom_path(classroom)

    expect(response).to have_http_status(:not_found)
    expect(classroom.reload).to be_active
  end

  it "blocks lifecycle mutations while the school is inactive" do
    classroom = create(:classroom, school: school)
    school.update!(active: false)
    sign_in admin

    patch deactivate_classroom_path(classroom)

    expect(response).to redirect_to(root_path)
    expect(classroom.reload).to be_active
  end
end
