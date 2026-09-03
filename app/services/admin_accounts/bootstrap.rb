# frozen_string_literal: true

module AdminAccounts
  class Bootstrap
    class Error < StandardError; end
    class AdministratorAlreadyExistsError < Error; end

    def self.call!(name:, email:, password:)
      User.transaction do
        if User.admin.exists?
          raise AdministratorAlreadyExistsError, "An administrator account already exists."
        end

        User.create!(
          name: name,
          email: email,
          password: password,
          password_confirmation: password,
          role: "admin",
          active: true,
          avatar_key: "admin"
        )
      end
    end
  end
end
