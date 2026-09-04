require "rails_helper"

RSpec.describe Teachers::SaveWithAssignment do
  def save(teacher:, school:, grade:, classroom: nil, attributes: {})
    described_class.call(
      teacher: teacher,
      attributes: attributes,
      school: school,
      membership_grade: grade,
      classroom_id: classroom&.id
    )
  end

  it "saves a school and grade without a classroom" do
    school = create(:school)
    teacher = build(:user, :teacher)

    result = save(teacher: teacher, school: school, grade: 5)

    expect(result).to be_success
    expect(teacher.school_membership).to have_attributes(school: school, grade: 5)
    expect(teacher.assigned_classroom).to be_nil
  end

  it "assigns one active classroom from the same school and grade" do
    membership = create(:school_membership, grade: 5)
    classroom = create(:classroom, school: membership.school, grade: 5)

    result = save(teacher: membership.user, school: membership.school, grade: 5, classroom: classroom)

    expect(result).to be_success
    expect(classroom.reload.teacher).to eq(membership.user)
  end

  it "moves the assignment atomically" do
    membership = create(:school_membership, grade: 5)
    old_classroom = create(:classroom, school: membership.school, grade: 5, teacher: membership.user)
    new_classroom = create(:classroom, school: membership.school, grade: 5)

    result = save(teacher: membership.user, school: membership.school, grade: 5, classroom: new_classroom)

    expect(result).to be_success
    expect(old_classroom.reload.teacher).to be_nil
    expect(new_classroom.reload.teacher).to eq(membership.user)
  end

  it "removes an assignment when no classroom is selected" do
    membership = create(:school_membership, grade: 5)
    classroom = create(:classroom, school: membership.school, grade: 5, teacher: membership.user)

    result = save(teacher: membership.user, school: membership.school, grade: 5)

    expect(result).to be_success
    expect(classroom.reload.teacher).to be_nil
  end

  it "rejects another school, another grade, inactive classrooms, and occupied classrooms" do
    membership = create(:school_membership, grade: 5)
    other_teacher = create(:school_membership, school: membership.school, grade: 5).user
    invalid_classrooms = [
      create(:classroom, grade: 5),
      create(:classroom, school: membership.school, grade: 6),
      create(:classroom, school: membership.school, grade: 5, active: false),
      create(:classroom, school: membership.school, grade: 5, teacher: other_teacher)
    ]

    invalid_classrooms.each do |classroom|
      result = save(teacher: membership.user, school: membership.school, grade: 5, classroom: classroom)
      expect(result).not_to be_success
      expect(membership.user.assigned_classroom).to be_nil
    end
  end

  it "rolls back profile, membership, and assignment changes on failure" do
    membership = create(:school_membership, grade: 5)
    classroom = create(:classroom, school: membership.school, grade: 5, teacher: membership.user)

    result = save(
      teacher: membership.user,
      school: membership.school,
      grade: 4,
      attributes: { name: "" }
    )

    expect(result).not_to be_success
    expect(membership.reload.grade).to eq(5)
    expect(classroom.reload.teacher).to eq(membership.user)
  end
end
