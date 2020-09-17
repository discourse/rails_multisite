# frozen_string_literal: true
require 'spec_helper'
require 'rails_multisite'
require 'rack/test'

describe RailsMultisite::Middleware do
  include Rack::Test::Methods

  let :config do
    {}
  end

  def app(config = {})

    RailsMultisite::ConnectionManagement.config_filename = 'spec/fixtures/two_dbs.yml'

    @app ||= Rack::Builder.new {
      use RailsMultisite::Middleware, config
      map '/html' do
        run (proc do |env|
          request = Rack::Request.new(env)
          [200, { 'Content-Type' => 'text/html' }, "<html><BODY><h1>#{request.hostname}</h1></BODY>\n \t</html>"]
        end)
      end
    }.to_app
  end

  after do
    RailsMultisite::ConnectionManagement.clear_settings!
  end

  describe '__ws lookup support' do
    it 'returns 200 for valid site' do

      RailsMultisite::ConnectionManagement.asset_hostname = "default.localhost"

      get 'http://second.localhost/html?__ws=default.localhost'
      expect(last_response).to be_ok
      expect(last_response.body).to include("second.localhost")
      expect(last_response.body).to_not include("default.localhost")

      get 'http://default.localhost/html?__ws=second.localhost'
      expect(last_response).to be_ok
      expect(last_response.body).to include("default.localhost")
      expect(last_response.body).to_not include("second.localhost")
    end

  end

  describe 'can whitelist a 404 to go to default site' do

    let :session do
      config = {
        db_lookup: lambda do |env|
          if env["rack.request.query_string"] == "allow"
            "default"
          else
            nil
          end
        end
      }
      mock_session = Rack::MockSession.new(app(config))
      Rack::Test::Session.new(mock_session)
    end

    it 'returns 404 for disallowed path' do
      session.get 'http://boom.com/html'
      expect(session.last_response).to be_not_found
    end

    it 'returns 200 for invalid sites' do
      session.get 'http://boom.com/html?allow'
      expect(session.last_response).to be_ok
    end
  end

  describe 'with a valid request' do

    it 'returns 200 for valid site' do
      get 'http://second.localhost/html'
      expect(last_response).to be_ok
    end

    it 'returns 200 for valid main site' do
      get 'http://default.localhost/html'
      expect(last_response).to be_ok
    end

    it 'returns 404 for invalid site' do
      get '/html'
      expect(last_response).to be_not_found
    end
  end
end
