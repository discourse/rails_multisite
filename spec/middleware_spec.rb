# frozen_string_literal: true
require "spec_helper"
require "rails_multisite"
require "rack/test"
require "json"

describe RailsMultisite::Middleware do
  include Rack::Test::Methods

  let :config do
    {}
  end

  def app(config = {})
    RailsMultisite::ConnectionManagement.config_filename = "spec/fixtures/two_dbs.yml"

    @app ||=
      Rack::Builder
        .new do
          use RailsMultisite::Middleware, config
          map "/html" do
            run(
              proc do |env|
                request = Rack::Request.new(env)
                [
                  200,
                  { "Content-Type" => "text/html" },
                  "<html><BODY><h1>#{request.hostname}</h1></BODY>\n \t</html>",
                ]
              end,
            )
          end
          map "/salts" do
            run(
              proc do |env|
                [
                  200,
                  { "Content-Type" => "application/json" },
                  env.slice(*RailsMultisite::CookieSalt::COOKIE_SALT_KEYS).to_json,
                ]
              end,
            )
          end
        end
        .to_app
  end

  after { RailsMultisite::ConnectionManagement.clear_settings! }

  describe "__ws lookup support" do
    it "returns 200 for valid site" do
      RailsMultisite::ConnectionManagement.asset_hostnames = %w[b.com default.localhost]

      get "http://second.localhost/html?__ws=default.localhost"
      expect(last_response).to be_ok
      expect(last_response.body).to include("second.localhost")
      expect(last_response.body).to_not include("default.localhost")

      get "http://default.localhost/html?__ws=second.localhost"
      expect(last_response).to be_ok
      expect(last_response.body).to include("default.localhost")
      expect(last_response.body).to_not include("second.localhost")

      RailsMultisite::ConnectionManagement.asset_hostnames = nil

      get "http://second.localhost/html?__ws=default.localhost"
      expect(last_response).to be_ok
      expect(last_response.body).to include("second.localhost")
      expect(last_response.body).to_not include("default.localhost")
    end
  end

  describe "can whitelist a 404 to go to default site" do
    let :session do
      config = {
        db_lookup:
          lambda do |env|
            if env["rack.request.query_string"] == "allow"
              "default"
            else
              nil
            end
          end,
      }
      mock_session = Rack::MockSession.new(app(config))
      Rack::Test::Session.new(mock_session)
    end

    it "returns 404 for disallowed path" do
      session.get "http://boom.com/html"
      expect(session.last_response).to be_not_found
    end

    it "returns 200 for invalid sites" do
      session.get "http://boom.com/html?allow"
      expect(session.last_response).to be_ok
    end
  end

  describe "with a valid request" do
    it "returns 200 for valid site" do
      get "http://second.localhost/html"
      expect(last_response).to be_ok
    end

    it "returns 200 for valid main site" do
      get "http://default.localhost/html"
      expect(last_response).to be_ok
    end

    it "returns 404 for invalid site" do
      get "/html"
      expect(last_response).to be_not_found
    end
  end

  describe "encrypted/signed cookie salts" do
    it "updates salts per-hostname" do
      get "http://default.localhost/salts"
      expect(last_response).to be_ok
      default_salts = JSON.parse(last_response.body)
      expect(default_salts.keys).to contain_exactly(*RailsMultisite::CookieSalt::COOKIE_SALT_KEYS)
      expect(default_salts.values).to all(include("default.localhost"))

      get "http://second.localhost/salts"
      expect(last_response).to be_ok
      second_salts = JSON.parse(last_response.body)
      expect(second_salts.keys).to contain_exactly(*RailsMultisite::CookieSalt::COOKIE_SALT_KEYS)
      expect(second_salts.values).to all(include("second.localhost"))

      leaked_previous_hostname = second_salts.values.any? { |v| v.include?("default.localhost") }
      expect(leaked_previous_hostname).to eq(false)
    end
  end
end
