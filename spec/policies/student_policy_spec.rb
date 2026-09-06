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
  end

  it "blocks Student self access when its classroom context is not operational" do
    classroom.update!(active: false)

    policy = described_class.new(student, student)
    expect(policy.show?).to eq(false)
    expect(policy.manage_own_student_pin?).to eq(false)
  end
end
