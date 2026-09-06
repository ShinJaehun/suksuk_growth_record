require "rails_helper"

RSpec.describe "Annual teacher authority" do
  let(:school) { create(:school) }
  let(:other_school) { create(:school) }

  def annual_teacher(school:, school_role:)
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: school_role)
  end

  it "does not grant manager authority to an annual member" do
    teacher = annual_teacher(school: school, school_role: "member")

    expect(TeacherManagementPolicy.new(teacher, User).access?).to be(false)
    expect(SchoolPolicy.new(teacher, school).manage_teachers?).to be(false)
  end

  it "grants own-school authority to an annual manager" do
    teacher = annual_teacher(school: school, school_role: "manager")
    classroom = create(:classroom, school: school)

    expect(TeacherManagementPolicy.new(teacher, User).access?).to be(true)
    expect(SchoolPolicy.new(teacher, school).manage_teachers?).to be(true)
    expect(ClassroomPolicy.new(teacher, classroom).show?).to be(true)
  end

  it "limits an annual manager to their annual School" do
    teacher = annual_teacher(school: school, school_role: "manager")

    expect(SchoolPolicy.new(teacher, school).manage_teachers?).to be(true)
    expect(SchoolPolicy.new(teacher, other_school).manage_teachers?).to be(false)
    expect(SchoolPolicy::Scope.new(teacher, School).resolve).to contain_exactly(school)
  end
end
