require "rails_helper"

RSpec.describe Classroom, type: :model do
  def annual_teacher(school:, grade:, **attributes)
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_grade: grade,
      **attributes)
  end
  it "generates a student login token" do
    classroom = create(:classroom, class_label: "토큰 교실")

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

  it "allows a class label with 50 characters" do
    classroom = build(:classroom, class_label: "가" * 50)

    expect(classroom).to be_valid
  end

  it "belongs to a school year" do
    school = create(:school)
    classroom = build(:classroom, annual_school: school)

    expect(classroom.school_year.school).to eq(school)
    expect(classroom).to be_valid
  end

  it "rejects a blank school year" do
    classroom = build(:classroom, school_year: nil)

    expect(classroom).not_to be_valid
    expect(classroom.errors[:school_year]).to be_present
  end

  it "normalizes a class label" do
    classroom = build(:classroom, class_label: " 가반 ")

    classroom.validate

    expect(classroom.class_label).to eq("가")
  end

  it "rejects a blank normalized class label" do
    classroom = build(:classroom, class_label: " 반 ")

    expect(classroom).not_to be_valid
    expect(classroom.errors[:class_label]).to be_present
  end

  it "rejects changing the school year of a persisted classroom" do
    classroom = create(:classroom)
    original_school_year = classroom.school_year

    expect(classroom.update(school_year: create(:school_year, :active))).to eq(false)
    expect(classroom.errors.added?(:school_year, :immutable)).to eq(true)
    expect(classroom.reload.school_year).to eq(original_school_year)
  end

  it "allows updating non-school-year settings" do
    classroom = create(:classroom)

    expect(classroom.update(
      class_label: "변경반",
      grade: 6
    )).to eq(true)
    expect(classroom.reload).to have_attributes(
      class_label: "변경",
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

  it "rejects a class label with more than 50 characters" do
    classroom = build(:classroom, class_label: "가" * 51)

    expect(classroom).not_to be_valid
  end

  it "rejects a duplicate label in the same school year and grade" do
    classroom = create(:classroom, grade: 4, class_label: "1")

    duplicate = build(:classroom, school_year: classroom.school_year, grade: 4, class_label: "1반")

    expect(duplicate).not_to be_valid
  end

  it "allows the same label in another school year" do
    first = create(:classroom, grade: 4, class_label: "1")
    other_year = create(:school_year, :active)

    expect(build(:classroom, school_year: other_year, grade: 4, class_label: "1")).to be_valid
  end

  it "returns the classroom's direct Student records" do
    classroom = create(:classroom)
    active_student = create(:student, classroom: classroom, active: true)
    inactive_student = create(:student, classroom: classroom, active: false)
    outside_student = create(:student)

    expect(classroom.students).to contain_exactly(active_student, inactive_student)
    expect(classroom.students).not_to include(outside_student)
  end

  describe "hard delete safety" do
    it "rejects deletion when homeroom assignment history exists" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)

      assignment = classroom.current_homeroom_assignment

      expect(classroom.destroy).to eq(false)
      expect(Classroom.exists?(classroom.id)).to eq(true)
      expect(User.exists?(teacher.id)).to eq(true)
      expect(HomeroomAssignment.exists?(assignment.id)).to eq(true)
    end

    it "rejects deletion when an active student exists" do
      classroom = create(:classroom)
      student = create(:student, classroom: classroom, active: true)

      expect(classroom.destroy).to eq(false)
      expect(Classroom.exists?(classroom.id)).to eq(true)
      expect(Student.exists?(student.id)).to eq(true)
      expect(classroom.errors.details[:base]).to include(error: :students_present)
    end

    it "rejects deletion when an inactive student exists" do
      classroom = create(:classroom)
      student = create(:student, classroom: classroom, active: false)

      expect(classroom.destroy).to eq(false)
      expect(Classroom.exists?(classroom.id)).to eq(true)
      expect(Student.exists?(student.id)).to eq(true)
    end

  end


  describe "teacher assignment" do
    it "preserves its teacher through deactivation and reactivation" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)

      classroom.update!(active: false)
      expect(classroom.reload.teacher).to eq(teacher)

      classroom.update!(active: true)

      expect(classroom.reload.teacher).to eq(teacher)
    end

    it "releases an inactive classroom assignment when its teacher is deactivated" do
      school = create(:school)
      teacher = annual_teacher(school: school, grade: 4)
      classroom = create(:classroom, annual_school: school, grade: 4, teacher: teacher)
      classroom.update!(active: false)

      teacher.update!(active: false)

      expect(classroom.reload.teacher).to be_nil
      expect(classroom.homeroom_assignments.last.ended_on).to eq(Date.current)

      teacher.update!(active: true)

      expect(classroom.reload.teacher).to be_nil
    end
  end
end
