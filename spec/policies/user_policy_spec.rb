require "rails_helper"

RSpec.describe UserPolicy do
  describe "generic user authorization" do
    let(:school) { create(:school) }
    let(:manager) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school,
        annual_school_role: "manager")
    end
    let(:member) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school,
        annual_school_role: "member")
    end

    it "keeps index, create, update, and scope admin-only" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, User).index?).to eq(true)
      expect(described_class.new(admin, User.new(role: :teacher)).create?).to eq(true)
      expect(described_class.new(manager, User).index?).to eq(false)
      expect(described_class.new(manager, User.new(role: :teacher)).create?).to eq(false)
      expect(described_class.new(manager, member).update?).to eq(false)
      expect(described_class::Scope.new(manager, User).resolve).to contain_exactly(manager)
    end
  end

  describe "#show?" do
    let(:teacher) { create(:user, :teacher) }
    let(:student) { create(:user, :student) }
    let(:classroom) { create(:classroom) }

    it "permits admin" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, student).show?).to eq(true)
    end

    it "permits a teacher for a student in the teacher's classroom" do
      assign_teacher(classroom, teacher)
      create(:classroom_membership, user: student, classroom: classroom, role: "student")

      expect(described_class.new(teacher, student).show?).to eq(true)
    end

    it "permits an assigned teacher to view an inactive student record" do
      assign_teacher(classroom, teacher)
      create(:classroom_membership, user: student, classroom: classroom, role: "student", status: "inactive")

      expect(described_class.new(teacher, student).show?).to eq(true)
    end

    it "rejects a teacher for a student outside the teacher's classroom" do
      other_classroom = create(:classroom)
      assign_teacher(classroom, teacher)
      create(:classroom_membership, user: student, classroom: other_classroom, role: "student")

      expect(described_class.new(teacher, student).show?).to eq(false)
    end

    it "permits a student for self" do
      expect(described_class.new(student, student).show?).to eq(true)
    end

    it "rejects a student for another student" do
      other_student = create(:user, :student)

      expect(described_class.new(student, other_student).show?).to eq(false)
    end
  end

  describe "#destroy_student?" do
    let(:teacher) { create(:user, :teacher) }
    let(:student) { create(:user, :student) }
    let(:classroom) { create(:classroom) }

    it "permits admin for a student account" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, student).destroy_student?).to eq(true)
    end

    it "permits a teacher for a student in the teacher's classroom" do
      assign_teacher(classroom, teacher)
      create(:classroom_membership, user: student, classroom: classroom, role: "student")

      expect(described_class.new(teacher, student).destroy_student?).to eq(true)
    end

    it "permits an assigned teacher to manage an inactive student account" do
      assign_teacher(classroom, teacher)
      create(:classroom_membership, user: student, classroom: classroom, role: "student", status: "inactive")

      expect(described_class.new(teacher, student).destroy_student?).to eq(true)
    end

    it "rejects a teacher for a student outside the teacher's classroom" do
      other_classroom = create(:classroom)
      assign_teacher(classroom, teacher)
      create(:classroom_membership, user: student, classroom: other_classroom, role: "student")

      expect(described_class.new(teacher, student).destroy_student?).to eq(false)
    end

    it "rejects a student for self" do
      expect(described_class.new(student, student).destroy_student?).to eq(false)
    end
  end

  describe "teacher status actions" do
    let(:school) { create(:school) }
    let(:manager) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school,
        annual_school_role: "manager")
    end
    let(:member) do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school,
        annual_school_role: "member")
    end

    it "allows admins to change teacher status" do
      admin = create(:user, :admin)
      expect(described_class.new(admin, member).deactivate_teacher?).to eq(true)
      member.update!(active: false)
      expect(described_class.new(admin, member).reactivate_teacher?).to eq(true)
    end

    it "allows a manager only for another same-school member" do
      expect(described_class.new(manager, member).deactivate_teacher?).to eq(true)
      expect(described_class.new(manager, manager).deactivate_teacher?).to eq(false)
      expect(described_class.new(member, manager).deactivate_teacher?).to eq(false)
      other_school = create(:school)
      other_teacher = create(:user, :teacher, :active_annual_teacher, annual_school: other_school)

      expect(described_class.new(manager, other_teacher).deactivate_teacher?).to eq(false)
      expect(described_class.new(manager, create(:user, :student)).deactivate_teacher?).to eq(false)
    end
  end
end
