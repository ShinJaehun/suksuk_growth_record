require "rails_helper"

RSpec.describe TeacherCredentialEvent, type: :model do
  let(:teacher) do
    create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))
  end

  it "records an allowed credential action for a teacher" do
    event = described_class.new(
      actor_user: create(:user, :admin),
      teacher_user: teacher,
      action: :temporary_password_issued
    )

    expect(event).to be_valid
  end

  it "rejects a non-teacher target" do
    event = described_class.new(
      actor_user: create(:user, :admin),
      teacher_user: create(:user, :admin),
      action: :temporary_password_reissued
    )

    expect(event).not_to be_valid
  end

  it "rejects unsupported actions" do
    event = described_class.new(
      actor_user: create(:user, :admin),
      teacher_user: teacher,
      action: "password_viewed"
    )

    expect(event).not_to be_valid
  end
end
