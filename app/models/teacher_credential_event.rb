class TeacherCredentialEvent < ApplicationRecord
  belongs_to :actor_user, class_name: "User", inverse_of: :issued_teacher_credential_events
  belongs_to :teacher_user, class_name: "User", inverse_of: :teacher_credential_events

  enum :action, {
    temporary_password_issued: "temporary_password_issued",
    temporary_password_reissued: "temporary_password_reissued"
  }, validate: true

  validate :teacher_target

  private

  def teacher_target
    errors.add(:teacher_user, :invalid) unless teacher_user&.teacher?
  end
end
