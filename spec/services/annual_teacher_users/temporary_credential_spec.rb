require "rails_helper"

RSpec.describe AnnualTeacherUsers::TemporaryCredential do
  def annual_teacher(**attributes)
    create(:user, :teacher, :active_annual_teacher,
      annual_school: create(:school), **attributes)
  end

  it "issues a temporary password and audit event in one transaction" do
    actor = create(:user, :admin)
    teacher = annual_teacher

    result = described_class.call(
      teacher:,
      actor:,
      action: :temporary_password_issued
    )

    expect(result).to be_success
    expect(result.temporary_password).to be_present
    expect(teacher.reload).to be_password_change_required
    expect(teacher.valid_password?(result.temporary_password)).to be(true)
    expect(result.event).to have_attributes(actor_user: actor, teacher_user: teacher)
  end

  it "replaces the old password and records a reissue" do
    teacher = annual_teacher(password: "old-password")

    result = described_class.call(
      teacher:,
      actor: create(:user, :admin),
      action: :temporary_password_reissued
    )

    expect(teacher.reload.valid_password?("old-password")).to be(false)
    expect(teacher.valid_password?(result.temporary_password)).to be(true)
    expect(result.event).to be_temporary_password_reissued
  end

  it "rolls back the credential when audit persistence fails" do
    teacher = annual_teacher(password: "old-password")
    allow(TeacherCredentialEvent).to receive(:create!).and_raise(
      ActiveRecord::RecordInvalid.new(TeacherCredentialEvent.new)
    )

    result = described_class.call(
      teacher:,
      actor: create(:user, :admin),
      action: :temporary_password_reissued
    )

    expect(result).not_to be_success
    expect(teacher.reload.valid_password?("old-password")).to be(true)
    expect(result.temporary_password).to be_nil
  end

  it "does not persist plaintext or password digests in the audit record" do
    columns = TeacherCredentialEvent.column_names

    expect(columns).not_to include("temporary_password", "password", "encrypted_password", "payload")
  end
end
