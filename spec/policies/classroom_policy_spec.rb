require "rails_helper"

RSpec.describe ClassroomPolicy do
  def annual_teacher(school:, school_role: "member", grade: nil)
    create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: school_role,
      annual_grade: grade)
  end

  describe "Scope" do
    let(:school) { create(:school) }
    let(:other_school) { create(:school) }
    let!(:classroom) { create(:classroom, school: school) }
    let!(:other_classroom) { create(:classroom, school: other_school) }

    it "returns every classroom for an admin" do
      admin = create(:user, :admin)

      expect(Pundit.policy_scope!(admin, Classroom)).to contain_exactly(classroom, other_classroom)
    end

    it "returns every classroom in the manager school" do
      manager = annual_teacher(school: school, school_role: "manager")

      expect(Pundit.policy_scope!(manager, Classroom)).to contain_exactly(classroom)
    end

    it "returns only assigned classrooms for a regular teacher" do
      assigned_classroom = create(:classroom, school: school)
      teacher = annual_teacher(school: school, grade: assigned_classroom.grade)
      assign_teacher(assigned_classroom, teacher)
      expect(Pundit.policy_scope!(teacher, Classroom)).to contain_exactly(assigned_classroom)
    end

    it "keeps the student membership scope" do
      student = create(:user, :student)
      create(:classroom_membership, classroom: classroom, user: student, role: :student)

      expect(Pundit.policy_scope!(student, Classroom)).to contain_exactly(classroom)
    end

    it "excludes classrooms with only an inactive student membership" do
      student = create(:user, :student)
      create(:classroom_membership, classroom: classroom, user: student, role: :student, status: :inactive)

      expect(Pundit.policy_scope!(student, Classroom)).to be_empty
    end
  end

  describe "#show?" do
    it "permits a manager to view an unassigned classroom in their school" do
      school = create(:school)
      classroom = create(:classroom, school: school)
      manager = annual_teacher(school: school, school_role: "manager")

      expect(described_class.new(manager, classroom).show?).to eq(true)
    end

    it "rejects a manager outside the classroom school" do
      classroom = create(:classroom)
      manager = annual_teacher(school: create(:school), school_role: "manager")

      expect(described_class.new(manager, classroom).show?).to eq(false)
    end
  end

  describe "#view_student_data?" do
    let(:school) { create(:school) }
    let(:classroom) { create(:classroom, school: school) }

    it "permits an admin" do
      expect(described_class.new(create(:user, :admin), classroom).view_student_data?).to eq(true)
    end

    it "permits a teacher assigned to the classroom" do
      teacher = annual_teacher(school: school, grade: classroom.grade)
      assign_teacher(classroom, teacher)
      expect(described_class.new(teacher, classroom).view_student_data?).to eq(true)
    end

    it "rejects a teacher outside the classroom" do
      teacher = annual_teacher(school: school)
      expect(described_class.new(teacher, classroom).view_student_data?).to eq(false)
    end

    it "rejects an unassigned school manager" do
      manager = annual_teacher(school: school, school_role: "manager")

      expect(described_class.new(manager, classroom).view_student_data?).to eq(false)
    end

    it "permits a manager who is also assigned to the classroom" do
      manager = annual_teacher(school: school, school_role: "manager", grade: classroom.grade)
      assign_teacher(classroom, manager)
      expect(described_class.new(manager, classroom).view_student_data?).to eq(true)
    end

    it "permits a student member of the classroom" do
      student = create(:user, :student)
      create(:classroom_membership, classroom: classroom, user: student, role: "student")

      expect(described_class.new(student, classroom).view_student_data?).to eq(true)
    end
  end

  describe "classroom operation permissions" do
    let(:school) { create(:school) }
    let(:classroom) { create(:classroom, school: school) }
    let(:manager) do
      annual_teacher(school: school, school_role: "manager", grade: classroom.grade)
    end

    it "keeps settings update access for an unassigned manager but blocks teacher operations" do
      policy = described_class.new(manager, classroom)

      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(false)
      expect(policy.destroy?).to eq(false)
    end

    it "combines manager access with existing classroom teacher permissions" do
      assign_teacher(classroom, manager)
      policy = described_class.new(manager, classroom)

      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(true)
      expect(policy.destroy?).to eq(false)
    end

  end

  describe "settings permissions" do
    let(:school) { create(:school) }
    let(:classroom) { create(:classroom, school: school) }

    it "allows an admin to render structure fields before a new classroom has a school" do
      policy = described_class.new(create(:user, :admin), Classroom.new)

      expect(policy.manage_structure?).to eq(true)
    end

    it "allows an admin to manage structure, operations, and members" do
      policy = described_class.new(create(:user, :admin), classroom)

      expect(policy.manage_structure?).to eq(true)
      expect(policy.manage_operations?).to eq(true)
      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(true)
    end

    it "allows an unassigned school manager to manage only structure" do
      manager = annual_teacher(school: school, school_role: "manager")
      policy = described_class.new(manager, classroom)

      expect(policy.manage_structure?).to eq(true)
      expect(policy.manage_operations?).to eq(false)
      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(false)
    end

    it "combines structure and teacher permissions for an assigned school manager" do
      manager = annual_teacher(school: school, school_role: "manager", grade: classroom.grade)
      assign_teacher(classroom, manager)
      policy = described_class.new(manager, classroom)

      expect(policy.manage_structure?).to eq(true)
      expect(policy.manage_operations?).to eq(true)
      expect(policy.update?).to eq(true)
      expect(policy.manage_members?).to eq(true)
    end

    it "allows an assigned regular teacher to manage operations and members only" do
      teacher = annual_teacher(school: school, grade: classroom.grade)
      assign_teacher(classroom, teacher)
      policy = described_class.new(teacher, classroom)

      expect(policy.manage_structure?).to eq(false)
      expect(policy.manage_operations?).to eq(true)
      expect(policy.update?).to eq(false)
      expect(policy.edit?).to eq(false)
      expect(policy.manage_members?).to eq(true)
    end

    it "rejects an unassigned teacher, student, and guest" do
      users = [annual_teacher(school: school), create(:user, :student), nil]

      users.each do |user|
        policy = described_class.new(user, classroom)

        expect(policy.manage_structure?).to eq(false)
        expect(policy.manage_operations?).to eq(false)
        expect(policy.update?).to eq(false)
        expect(policy.manage_members?).to eq(false)
      end
    end
  end

  describe "lifecycle permissions" do
    let(:school) { create(:school) }
    let(:active_classroom) { create(:classroom, school: school) }
    let(:inactive_classroom) { create(:classroom, school: school, active: false) }

    it "allows an admin to deactivate active and reactivate inactive classrooms" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, active_classroom).deactivate?).to eq(true)
      expect(described_class.new(admin, inactive_classroom).reactivate?).to eq(true)
    end

    it "allows only the classroom school's manager" do
      manager = annual_teacher(school: school, school_role: "manager")
      other_manager = annual_teacher(school: create(:school), school_role: "manager")

      expect(described_class.new(manager, active_classroom).deactivate?).to eq(true)
      expect(described_class.new(manager, inactive_classroom).reactivate?).to eq(true)
      expect(described_class.new(other_manager, active_classroom).deactivate?).to eq(false)
      expect(described_class.new(other_manager, inactive_classroom).reactivate?).to eq(false)
    end

    it "rejects ordinary teachers and students" do
      teacher = annual_teacher(school: school, grade: active_classroom.grade)
      student = create(:user, :student)
      assign_teacher(active_classroom, teacher)
      create(:classroom_membership, classroom: active_classroom, user: student, role: :student)

      [teacher, student].each do |user|
        expect(described_class.new(user, active_classroom).deactivate?).to eq(false)
        expect(described_class.new(user, inactive_classroom).reactivate?).to eq(false)
      end
    end

    it "rejects lifecycle mutations inside an inactive school" do
      admin = create(:user, :admin)
      school.update!(active: false)

      expect(described_class.new(admin, active_classroom).deactivate?).to eq(false)
      expect(described_class.new(admin, inactive_classroom).reactivate?).to eq(false)
    end

    it "blocks ordinary operations and member management in inactive classrooms" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, inactive_classroom).edit?).to eq(true)
      expect(described_class.new(admin, inactive_classroom).manage_structure?).to eq(false)
      expect(described_class.new(admin, inactive_classroom).manage_operations?).to eq(false)
      expect(described_class.new(admin, inactive_classroom).manage_members?).to eq(false)
      expect(described_class.new(admin, inactive_classroom).update?).to eq(false)
    end
  end

  describe "#destroy?" do
    let(:school) { create(:school) }
    let(:classroom) { create(:classroom, school: school) }

    it "permits an admin" do
      expect(described_class.new(create(:user, :admin), classroom).destroy?).to eq(true)
    end

    it "rejects an assigned teacher" do
      teacher = annual_teacher(school: school, grade: classroom.grade)
      assign_teacher(classroom, teacher)
      expect(described_class.new(teacher, classroom).destroy?).to eq(false)
    end

    it "rejects an unassigned teacher" do
      teacher = annual_teacher(school: school)
      expect(described_class.new(teacher, classroom).destroy?).to eq(false)
    end

    it "rejects an unassigned school manager" do
      manager = annual_teacher(school: school, school_role: "manager")

      expect(described_class.new(manager, classroom).destroy?).to eq(false)
    end

    it "rejects a school manager who is also an assigned teacher" do
      manager = annual_teacher(school: school, school_role: "manager", grade: classroom.grade)
      assign_teacher(classroom, manager)
      expect(described_class.new(manager, classroom).destroy?).to eq(false)
    end

    it "rejects a student" do
      expect(described_class.new(create(:user, :student), classroom).destroy?).to eq(false)
    end

    it "rejects a guest" do
      expect(described_class.new(nil, classroom).destroy?).to eq(false)
    end
  end

end
