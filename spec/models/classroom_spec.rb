require "rails_helper"

RSpec.describe Classroom, type: :model do
  it "generates a student login token" do
    classroom = create(:classroom, name: "토큰 교실")

    expect(classroom.student_login_token).to be_present
  end

  it "is active by default" do
    expect(described_class.new).to be_active
  end

  it "scopes active and inactive classrooms" do
    active_classroom = create(:classroom)
    inactive_classroom = create(:classroom, active: false)

    expect(described_class.active).to contain_exactly(active_classroom)
    expect(described_class.inactive).to contain_exactly(inactive_classroom)
  end

  it "allows a name with 50 characters" do
    classroom = build(:classroom, name: "가" * 50)

    expect(classroom).to be_valid
  end

  it "can belong to a school" do
    school = create(:school)
    classroom = build(:classroom, school: school)

    expect(classroom.school).to eq(school)
    expect(classroom).to be_valid
  end

  it "rejects a blank school" do
    classroom = build(:classroom, school: nil)

    expect(classroom).not_to be_valid
    expect(classroom.errors[:school]).to be_present
  end

  it "rejects a school id that does not exist" do
    classroom = build(:classroom, school: nil, school_id: School.maximum(:id).to_i + 10_000)

    expect(classroom).not_to be_valid
    expect(classroom.errors[:school]).to be_present
  end

  it "rejects changing the school of an empty persisted classroom" do
    original_school = create(:school)
    classroom = create(:classroom, school: original_school)

    expect(classroom.update(school: create(:school))).to eq(false)
    expect(classroom.errors.added?(:school, :immutable)).to eq(true)
    expect(classroom.reload.school).to eq(original_school)
  end

  it "allows updating non-school settings" do
    classroom = create(:classroom)

    expect(classroom.update(
      name: "변경 교실",
      grade: 6
    )).to eq(true)
    expect(classroom.reload).to have_attributes(
      name: "변경 교실",
      grade: 6
    )
  end

  it "allows grades 1 and 6" do
    [1, 6].each do |grade|
      classroom = build(:classroom, grade: grade)

      expect(classroom).to be_valid
    end
  end

  it "rejects a blank grade" do
    classroom = build(:classroom, grade: nil)

    expect(classroom).not_to be_valid
    expect(classroom.errors[:grade]).to be_present
  end

  it "rejects grades outside the elementary range" do
    [0, 7].each do |grade|
      classroom = build(:classroom, grade: grade)

      expect(classroom).not_to be_valid
    end
  end

  it "rejects a non-integer grade" do
    classroom = build(:classroom, grade: 4.5)

    expect(classroom).not_to be_valid
  end

  it "rejects a name with more than 50 characters" do
    classroom = build(:classroom, name: "가" * 51)

    expect(classroom).not_to be_valid
  end

  it "returns only active student memberships from students" do
    classroom = create(:classroom)
    active_student = create(:user, :student)
    inactive_student = create(:user, :student)
    teacher = create(:user, :teacher)
    create(:classroom_membership, classroom: classroom, user: active_student, role: "student")
    create(:classroom_membership, classroom: classroom, user: inactive_student, role: "student", status: "inactive")
    create(:classroom_membership, classroom: classroom, user: teacher, role: "teacher")

    expect(classroom.students).to contain_exactly(active_student)
  end

  describe "hard delete safety" do
    it "allows deletion when only teacher memberships exist" do
      classroom = create(:classroom)
      teacher = create(:user, :teacher)
      create(:classroom_membership, classroom: classroom, user: teacher, role: "teacher")

      expect(classroom.destroy).to be_truthy
      expect(Classroom.exists?(classroom.id)).to eq(false)
      expect(User.exists?(teacher.id)).to eq(true)
      expect(ClassroomMembership.where(classroom_id: classroom.id)).to be_empty
    end

    it "rejects deletion when an active student membership exists" do
      classroom = create(:classroom)
      membership = create(:classroom_membership, classroom: classroom, role: "student", status: "active")

      expect(classroom.destroy).to eq(false)
      expect(Classroom.exists?(classroom.id)).to eq(true)
      expect(ClassroomMembership.exists?(membership.id)).to eq(true)
      expect(classroom.errors.details[:base]).to include(error: :students_present)
    end

    it "rejects deletion when an inactive student membership exists" do
      classroom = create(:classroom)
      membership = create(:classroom_membership, classroom: classroom, role: "student", status: "inactive")

      expect(classroom.destroy).to eq(false)
      expect(Classroom.exists?(classroom.id)).to eq(true)
      expect(ClassroomMembership.exists?(membership.id)).to eq(true)
    end

  end
end
