# frozen_string_literal: true

module RailsMultisite
  class CookieSalt
    COOKIE_SALT_KEYS = %w[
      action_dispatch.signed_cookie_salt
      action_dispatch.encrypted_cookie_salt
      action_dispatch.encrypted_signed_cookie_salt
      action_dispatch.authenticated_encrypted_cookie_salt
    ]

    def self.update_cookie_salts(env:, host:)
      COOKIE_SALT_KEYS.each { |key| env[key] = "#{env[key]} #{host}" }
    end
  end
end
