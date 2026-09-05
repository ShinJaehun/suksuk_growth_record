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

  it "updates teacher profile attributes" do
    teacher = create(:user, :teacher, name: "변경 전")

    result = save(teacher: teacher, school: nil, grade: nil, attributes: { name: "변경 후" })

    expect(result).to be_success
    expect(teacher.reload.name).to eq("변경 후")
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

  it "rejects a non-teacher" do
    student = create(:user, :student)

    expect(save(teacher: student, school: create(:school), grade: 4)).not_to be_success
  end

  it "rejects a nonexistent classroom" do
    teacher = build(:user, :teacher)
    result = described_class.call(teacher: teacher, attributes: {}, school: create(:school),
                                  membership_grade: 4, classroom_id: Classroom.maximum(:id).to_i + 10_000)

    expect(result).not_to be_success
  end

  it "rejects a classroom without a school selection" do
    teacher = build(:user, :teacher)
    classroom = create(:classroom)

    expect(save(teacher: teacher, school: nil, grade: 4, classroom: classroom)).not_to be_success
  end

  it "rejects an inactive teacher" do
    membership = create(:school_membership, grade: 4)
    membership.user.update!(active: false)
    classroom = create(:classroom, school: membership.school, grade: 4)

    expect(save(teacher: membership.user, school: membership.school, grade: 4,
                classroom: classroom)).not_to be_success
  end

  it "rejects a newly selected inactive school" do
    teacher = build(:user, :teacher)

    expect(save(teacher: teacher, school: create(:school, active: false), grade: 4)).not_to be_success
  end

  it "allows a profile update while retaining the existing inactive school" do
    membership = create(:school_membership, grade: 4)
    membership.school.update!(active: false)

    result = save(teacher: membership.user, school: membership.school, grade: 4,
                  attributes: { name: "변경 후" })

    expect(result).to be_success
    expect(membership.user.reload.name).to eq("변경 후")
  end

  it "preserves a manager role in the same school" do
    membership = create(:school_membership, :manager, grade: 4)

    expect(save(teacher: membership.user, school: membership.school, grade: 4)).to be_success
    expect(membership.reload).to be_manager
  end

  it "changes a manager to a member when moving schools" do
    membership = create(:school_membership, :manager, grade: 4)

    expect(save(teacher: membership.user, school: create(:school), grade: 4)).to be_success
    expect(membership.reload).to be_member
  end

  it "removes the school membership and assignment when school is nil" do
    membership = create(:school_membership, grade: 4)
    classroom = create(:classroom, school: membership.school, grade: 4, teacher: membership.user)

    expect(save(teacher: membership.user, school: nil, grade: nil)).to be_success
    expect(membership.user.reload.school_membership).to be_nil
    expect(classroom.reload.teacher).to be_nil
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
