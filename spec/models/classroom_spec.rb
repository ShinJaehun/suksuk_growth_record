require "rails_helper"

RSpec.describe Classroom, type: :model do
  def annual_teacher(school:, grade:, **attributes)
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: grade,
      **attributes)
  end
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
    create(:classroom_membership, classroom: classroom, user: active_student, role: "student")
    create(:classroom_membership, classroom: classroom, user: inactive_student, role: "student", status: "inactive")

    expect(classroom.students).to contain_exactly(active_student)
  end

  describe "hard delete safety" do
    it "allows deletion when a teacher is assigned and there are no students" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      classroom = create(:classroom, school: school, grade: 4, teacher: teacher)

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


  describe "teacher assignment" do
    it "allows one active teacher from the same school and grade" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      classroom = build(:classroom, school: school, grade: 4, teacher: teacher)

      expect(classroom).to be_valid
    end

    it "rejects assigning one teacher to two classrooms" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      create(:classroom, school: school, grade: 4, teacher: teacher)

      duplicate = build(:classroom, school: school, grade: 4, teacher: teacher)
      expect(duplicate).not_to be_valid
    end

    it "rejects school, grade, lifecycle, and role mismatches" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      invalid = [
        build(:classroom, school: create(:school), grade: 4, teacher: teacher),
        build(:classroom, school: school, grade: 5, teacher: teacher),
        build(:classroom, school: school, grade: 4, active: false, teacher: teacher),
        build(:classroom, teacher: create(:user, :student))
      ]

      expect(invalid).to all(be_invalid)
    end

    it "preserves its teacher through deactivation and reactivation" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      classroom = create(:classroom, school: school, grade: 4, teacher: teacher)

      classroom.update!(active: false)
      expect(classroom.reload.teacher).to eq(teacher)

      classroom.update!(active: true)

      expect(classroom.reload.teacher).to eq(teacher)
    end

    it "rejects assigning or replacing a teacher while inactive" do
      school = create(:school)
      first_teacher = annual_teacher(school: school, grade: 4)
      second_teacher = annual_teacher(school: school, grade: 4)
      unassigned = create(:classroom, school: school, grade: 4, active: false)
      assigned = create(:classroom, school: school, grade: 4, teacher: first_teacher)
      assigned.update!(active: false)

      expect(unassigned.update(teacher: second_teacher)).to eq(false)
      expect(assigned.update(teacher: second_teacher)).to eq(false)
      expect(assigned.reload.teacher).to eq(first_teacher)
    end

    it "releases an inactive classroom assignment when its teacher is deactivated" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      classroom = create(:classroom, school: school, grade: 4, teacher: teacher)
      classroom.update!(active: false)

      teacher.update!(active: false)

      expect(classroom.reload.teacher).to be_nil
    end
  end
end
