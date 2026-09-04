require "rails_helper"

RSpec.describe TeacherManagementPolicy do
  let(:school) { create(:school) }
  let(:manager) { create(:school_membership, :manager, school: school).user }
  let(:member) { create(:school_membership, school: school).user }
  let(:outside_teacher) { create(:school_membership, school: create(:school)).user }

  it "allows admins and managers to access and create" do
    admin = create(:user, :admin)

    expect(described_class.new(admin, User).access?).to eq(true)
    expect(described_class.new(admin, User.new(role: :teacher)).create?).to eq(true)
    expect(described_class.new(manager, User).access?).to eq(true)
    expect(described_class.new(manager, User.new(role: :teacher)).create?).to eq(true)
  end

  it "limits manager profile management and scope to their school" do
    expect(described_class.new(manager, member).update_profile?).to eq(true)
    expect(described_class.new(manager, manager).update_profile?).to eq(true)
    expect(described_class.new(manager, outside_teacher).update_profile?).to eq(false)
    expect(described_class::Scope.new(manager, User).resolve).to contain_exactly(manager, member)
  end

  it "rejects regular teachers" do
    expect(described_class.new(member, User).access?).to eq(false)
    expect(described_class.new(member, User.new(role: :teacher)).create?).to eq(false)
  end
end
