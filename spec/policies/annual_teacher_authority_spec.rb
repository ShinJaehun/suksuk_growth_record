require "rails_helper"

RSpec.describe "Annual teacher authority" do
  let(:school) { create(:school) }
  let(:other_school) { create(:school) }

  def annual_teacher(school:, school_role:)
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: school_role)
  end

  it "does not promote an annual member through a legacy manager membership" do
    teacher = annual_teacher(school: school, school_role: "member")
    create(:school_membership, :manager, school: school, user: teacher)

    expect(TeacherManagementPolicy.new(teacher, User).access?).to be(false)
    expect(SchoolPolicy.new(teacher, school).manage_teachers?).to be(false)
  end

  it "grants own-school authority to an annual manager despite a legacy member membership" do
    teacher = annual_teacher(school: school, school_role: "manager")
    create(:school_membership, school: school, user: teacher)

    expect(TeacherManagementPolicy.new(teacher, User).access?).to be(true)
    expect(SchoolPolicy.new(teacher, school).manage_teachers?).to be(true)
  end

  it "does not require a SchoolMembership for annual manager authority" do
    teacher = annual_teacher(school: school, school_role: "manager")
    classroom = create(:classroom, school: school)

    expect(teacher.school_membership).to be_nil
    expect(TeacherManagementPolicy.new(teacher, User).access?).to be(true)
    expect(SchoolPolicy.new(teacher, school).manage_teachers?).to be(true)
    expect(ClassroomPolicy.new(teacher, classroom).show?).to be(true)
  end

  it "uses the annual School instead of a conflicting legacy membership School" do
    teacher = annual_teacher(school: school, school_role: "manager")
    create(:school_membership, :manager, school: other_school, user: teacher)

    expect(SchoolPolicy.new(teacher, school).manage_teachers?).to be(true)
    expect(SchoolPolicy.new(teacher, other_school).manage_teachers?).to be(false)
    expect(SchoolPolicy::Scope.new(teacher, School).resolve).to contain_exactly(school)
  end
end
