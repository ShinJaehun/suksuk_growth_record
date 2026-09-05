require "rails_helper"

RSpec.describe SchoolMemberships::Backfill do
  it "backfills teacher memberships idempotently while preserving managers and excluding students" do
    school = create(:school)
    classroom = create(:classroom, school: school)
    teacher = create(:user, :teacher)
    manager_membership = create(:school_membership, :manager, school: school)
    student = create(:user, :student)
    classroom.update_columns(teacher_id: teacher.id)
    create(:classroom_membership, classroom: classroom, user: student, role: :student)
    expect(teacher.school_membership).to be_nil

    first = described_class.call
    second = described_class.call

    expect(first.created).to eq(1)
    expect(second.created).to eq(0)
    expect(second.conflicts).to eq(0)
    expect(teacher.reload.school_membership).to be_member
    expect(manager_membership.reload).to be_manager
    expect(student.reload.school_membership).to be_nil
  end

  it "counts cross-school conflicts without changing memberships or assignments" do
    first_school = create(:school)
    other_classroom = create(:classroom, school: create(:school))
    membership = create(:school_membership, school: first_school)
    other_classroom.update_columns(teacher_id: membership.user_id)

    result = described_class.call

    expect(result.conflicts).to eq(1)
    expect(membership.reload.school).to eq(first_school)
    expect(other_classroom.reload.teacher).to eq(membership.user)
  end
end
