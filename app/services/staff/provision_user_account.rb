module Staff
  class ProvisionUserAccount
    def initialize(email:)
      @email = email.to_s.strip.downcase
    end

    def call
      existing_user = User.find_by(email: @email)
      return existing_user if existing_user

      password = SecureRandom.base58(48)

      User.create!(
        email: @email,
        password: password,
        password_confirmation: password
      )
    rescue ActiveRecord::RecordNotUnique
      User.find_by!(email: @email)
    rescue ActiveRecord::RecordInvalid => error
      existing_user = User.find_by(email: @email)
      raise unless existing_user && error.record.errors.added?(:email, :taken)

      existing_user
    end
  end
end
