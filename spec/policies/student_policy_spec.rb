require "rails_helper"

RSpec.describe StudentPolicy do
  let(:school) { create(:school) }
  let(:classroom) { create(:classroom, annual_school: school) }
  let(:student) { create(:student, classroom: classroom) }

  it "allows an eligible Student to read itself and manage its own PIN" do
    policy = described_class.new(student, student)

    expect(policy.show?).to eq(true)
    expect(policy.manage_own_student_pin?).to eq(true)
  end

  it "rejects another Student" do
    policy = described_class.new(create(:student), student)

    expect(policy.show?).to eq(false)
    expect(policy.manage_own_student_pin?).to eq(false)
  end

  it "allows the active homeroom teacher to read its classroom Student" do
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school, annual_grade: classroom.grade)
    assign_teacher(classroom, teacher)

    expect(described_class.new(teacher, student).show?).to eq(true)
    expect(described_class.new(teacher, student).manage?).to eq(true)
  end

  it "allows an admin to manage an operational Classroom Student" do
    expect(described_class.new(create(:user, :admin), student).manage?).to eq(true)
  end

  it "rejects a guest" do
    policy = described_class.new(nil, student)

    expect(policy.show?).to eq(false)
    expect(policy.manage?).to eq(false)
    expect(policy.manage_own_student_pin?).to eq(false)
  end

  it "blocks management when the classroom is not operational" do
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: school, annual_grade: classroom.grade)
    assign_teacher(classroom, teacher)
    admin = create(:user, :admin)
    classroom.update!(active: false)

    expect(described_class.new(teacher, student).manage?).to eq(false)
    expect(described_class.new(admin, student).manage?).to eq(false)
  end

  it "blocks Student self access when its classroom context is not operational" do
    classroom.update!(active: false)

    policy = described_class.new(student, student)
    expect(policy.show?).to eq(false)
    expect(policy.manage_own_student_pin?).to eq(false)
  end
  describe "migrated legacy student authorization contracts" do
    let(:teacher) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school, annual_grade: classroom.grade)
    end

    it "permits an admin to read a Student" do
      expect(described_class.new(create(:user, :admin), student).show?).to eq(true)
    end

    it "permits the assigned teacher to read a Student" do
      assign_teacher(classroom, teacher)

      expect(described_class.new(teacher, student).show?).to eq(true)
    end

    it "permits the assigned teacher to read an inactive Student record" do
      assign_teacher(classroom, teacher)
      student.update!(active: false)

      expect(described_class.new(teacher, student).show?).to eq(true)
    end

    it "rejects a teacher for a Student outside the teacher's classroom" do
      assign_teacher(classroom, teacher)
      other_student = create(:student, classroom: create(:classroom))

      expect(described_class.new(teacher, other_student).show?).to eq(false)
    end

    it "permits a Student to read itself" do
      expect(described_class.new(student, student).show?).to eq(true)
    end

    it "rejects a Student reading another Student" do
      expect(described_class.new(student, create(:student)).show?).to eq(false)
    end

    it "permits an admin to manage an operational Student" do
      expect(described_class.new(create(:user, :admin), student).manage?).to eq(true)
    end

    it "permits the assigned teacher to manage a Student" do
      assign_teacher(classroom, teacher)

      expect(described_class.new(teacher, student).manage?).to eq(true)
    end

    it "permits the assigned teacher to manage an inactive Student record" do
      assign_teacher(classroom, teacher)
      student.update!(active: false)

      expect(described_class.new(teacher, student).manage?).to eq(true)
    end

    it "rejects a teacher managing a Student outside the teacher's classroom" do
      assign_teacher(classroom, teacher)
      other_student = create(:student, classroom: create(:classroom))

      expect(described_class.new(teacher, other_student).manage?).to eq(false)
    end

    it "rejects a Student managing itself through teacher/admin management authority" do
      expect(described_class.new(student, student).manage?).to eq(false)
    end
  end

end
