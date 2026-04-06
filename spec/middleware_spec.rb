# frozen_string_literal: true
require 'spec_helper'
require 'rails_multisite'
require 'rack/test'
require 'json'

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
        run(proc do |env|
          request = Rack::Request.new(env)
          [200, { 'Content-Type' => 'text/html' }, "<html><BODY><h1>#{request.hostname}</h1></BODY>\n \t</html>"]
        end)
      end
      map '/salts' do
        run(proc do |env|
          [200, { 'Content-Type' => 'application/json' }, env.slice(*RailsMultisite::CookieSalt::COOKIE_SALT_KEYS).to_json]
        end)
      end
    }.to_app
  end

  after do
    RailsMultisite::ConnectionManagement.clear_settings!
    @app = nil
  end

  describe '__ws lookup support' do
    it 'returns 200 for valid site' do

      RailsMultisite::ConnectionManagement.asset_hostnames = ["b.com", "default.localhost"]

      get 'http://second.localhost/html?__ws=default.localhost'
      expect(last_response).to be_ok
      expect(last_response.body).to include("second.localhost")
      expect(last_response.body).to_not include("default.localhost")

      get 'http://default.localhost/html?__ws=second.localhost'
      expect(last_response).to be_ok
      expect(last_response.body).to include("default.localhost")
      expect(last_response.body).to_not include("second.localhost")

      RailsMultisite::ConnectionManagement.asset_hostnames = nil

      get 'http://second.localhost/html?__ws=default.localhost'
      expect(last_response).to be_ok
      expect(last_response.body).to include("second.localhost")
      expect(last_response.body).to_not include("default.localhost")
    end

  end

  describe 'can whitelist a 404 to go to default site' do

    let :session do
      config = {
        db_lookup: lambda do |env|
          if env["QUERY_STRING"] == "allow"
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

  describe 'path-prefix config per site' do
    before { ActiveRecord::Base.establish_connection }
    after  { ActiveRecord::Base.remove_connection }

    def app(_config = {})
      RailsMultisite::ConnectionManagement.config_filename = 'spec/fixtures/two_dbs_path_prefix.yml'

      Rack::Builder.new {
        use RailsMultisite::Middleware
        run(proc do |env|
          db     = RailsMultisite::ConnectionManagement.current_db
          prefix = RailsMultisite::ConnectionManagement.current_path_prefix
          [200,
           { 'Content-Type' => 'application/json' },
           [{ db: db, path_prefix: prefix,
              script_name: env["SCRIPT_NAME"],
              path_info: env["PATH_INFO"] }.to_json]]
        end)
      }.to_app
    end

    it 'routes /site_a/* to site_a db' do
      get 'http://site_a.localhost/site_a/slugs'
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["db"]).to eq("site_a")
      expect(body["path_prefix"]).to eq("/site_a")
    end

    it 'routes /site_b/* to site_b db' do
      get 'http://site_b.localhost/site_b/slugs/1'
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["db"]).to eq("site_b")
      expect(body["path_prefix"]).to eq("/site_b")
    end

    it 'sets SCRIPT_NAME to the matched prefix' do
      get 'http://site_a.localhost/site_a/slugs'
      body = JSON.parse(last_response.body)
      expect(body["script_name"]).to eq("/site_a")
    end

    it 'strips the prefix from PATH_INFO' do
      get 'http://site_a.localhost/site_a/slugs/1'
      body = JSON.parse(last_response.body)
      expect(body["path_info"]).to eq("/slugs/1")
    end

    it 'sets PATH_INFO to / when request hits the prefix root' do
      get 'http://site_a.localhost/site_a'
      body = JSON.parse(last_response.body)
      expect(body["path_info"]).to eq("/")
    end

    it 'returns 404 for wrong prefix on a path-prefix hostname' do
      get 'http://site_a.localhost/unknown/page'
      expect(last_response).to be_not_found
    end

    it 'returns 404 for missing prefix on a path-prefix hostname' do
      get 'http://site_a.localhost/page'
      expect(last_response).to be_not_found
    end

    it 'returns 404 for unknown hostname' do
      get 'http://unknown.localhost/site_a/posts'
      expect(last_response).to be_not_found
    end

    describe 'with default_db_path_prefix' do
      before do
        load_db_config('database_with_path_prefix.yml')
        RailsMultisite::ConnectionManagement.config_filename = 'spec/fixtures/two_dbs_path_prefix.yml'
      end

      after { load_db_config('database.yml') }

      it 'routes the relative URL root path to the default db' do
        get 'http://default.localhost/root/posts'
        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body["db"]).to eq("default")
      end

      it 'sets SCRIPT_NAME to the relative URL root' do
        get 'http://default.localhost/root/posts'
        body = JSON.parse(last_response.body)
        expect(body["script_name"]).to eq("/root")
      end

      it 'strips the relative URL root from PATH_INFO' do
        get 'http://default.localhost/root/posts'
        body = JSON.parse(last_response.body)
        expect(body["path_info"]).to eq("/posts")
      end

      it 'returns 404 for an unrecognized prefix on the default hostname' do
        get 'http://default.localhost/unknown/posts'
        expect(last_response).to be_not_found
      end

      it 'still routes other db path prefixes independently' do
        get 'http://site_a.localhost/site_a/posts'
        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body["db"]).to eq("site_a")
        expect(body["script_name"]).to eq("/site_a")
      end

      it 'does not apply default prefix to other hostnames' do
        get 'http://site_a.localhost/root/posts'
        expect(last_response).to be_not_found
      end
    end
  end

  describe 'encrypted/signed cookie salts' do
    it 'updates salts per-hostname' do
      get 'http://default.localhost/salts'
      expect(last_response).to be_ok
      default_salts = JSON.parse(last_response.body)
      expect(default_salts.keys).to contain_exactly(*RailsMultisite::CookieSalt::COOKIE_SALT_KEYS)
      expect(default_salts.values).to all(include("default.localhost"))

      get 'http://second.localhost/salts'
      expect(last_response).to be_ok
      second_salts = JSON.parse(last_response.body)
      expect(second_salts.keys).to contain_exactly(*RailsMultisite::CookieSalt::COOKIE_SALT_KEYS)
      expect(second_salts.values).to all(include("second.localhost"))

      leaked_previous_hostname = second_salts.values.any? { |v| v.include?("default.localhost") }
      expect(leaked_previous_hostname).to eq(false)
    end
  end
end
