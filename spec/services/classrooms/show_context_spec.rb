require "rails_helper"

RSpec.describe Classrooms::ShowContext do
  let(:classroom) { create(:classroom) }

  it "returns active students in roster order" do
    second = create(:user, :student, name: "둘째")
    first = create(:user, :student, name: "첫째")
    inactive = create(:user, :student)
    second_membership = create(:classroom_membership, classroom: classroom, user: second, student_number: 2)
    first_membership = create(:classroom_membership, classroom: classroom, user: first, student_number: 1)
    create(:classroom_membership, classroom: classroom, user: inactive, status: "inactive")

    context = described_class.new(classroom: classroom)

    expect(context.student_memberships.to_a).to eq([first_membership, second_membership])
    expect(context.students.pluck(:id)).to contain_exactly(first.id, second.id)
  end

  it "preloads avatar attachments for active students" do
    student = create(:user, :student, avatar_key: "boy01")
    membership = create(:classroom_membership, classroom: classroom, user: student)

    loaded_membership = described_class.new(classroom: classroom).student_memberships.load.first

    expect(loaded_membership.id).to eq(membership.id)
    expect(loaded_membership.association(:user)).to be_loaded
    expect(loaded_membership.user.association(:avatar_attachment)).to be_loaded
  end

  it "returns the assigned teacher" do
    teacher = create(:user, :teacher)
    assign_teacher(classroom, teacher)

    expect(described_class.new(classroom: classroom).homeroom_teachers).to eq([teacher])
  end
end
