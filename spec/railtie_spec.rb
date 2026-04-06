# frozen_string_literal: true
require 'spec_helper'
require 'rails_multisite'
require 'action_controller'

describe RailsMultisite::Railtie do
  let(:conn) { RailsMultisite::ConnectionManagement }

  # Runs only the RailsMultisite.init initializer without full app boot.
  # Use for ConnectionManagement and ActionController assertions — avoids
  # the freeze-after-initialize! limitation.
  def run_initializer(multisite_fixture: nil)
    config_path = fixture_path(multisite_fixture) if multisite_fixture
    app = Class.new(Rails::Application) do
      config.eager_load = false
      config.skip_multisite_middleware = true
      # Always set explicitly to prevent Rails config inheritance across examples
      config.multisite_config_path = config_path
    end
    RailsMultisite::Railtie.initializers
      .find { |i| i.name == 'RailsMultisite.init' }
      .run(app)
    app
  end

  before do
    Rails.application = nil
    ActiveRecord::Base.establish_connection
  end

  after do
    conn.clear_settings!
    ActiveRecord::Base.remove_connection
    Rails.application = nil
    if ActionController::Base.config.singleton_class.method_defined?(:relative_url_root)
      ActionController::Base.config.singleton_class.remove_method(:relative_url_root)
    end
  end

  describe 'app.config.multisite' do
    it 'is false when no config file is present' do
      app = run_initializer
      expect(app.config.multisite).to eq(false)
    end

    it 'is true when a config file is present' do
      app = run_initializer(multisite_fixture: 'two_dbs.yml')
      expect(app.config.multisite).to eq(true)
    end
  end

  describe 'app.config.multisite_config_path' do
    it 'loads the specified config file into ConnectionManagement' do
      run_initializer(multisite_fixture: 'two_dbs.yml')
      expect(conn.all_dbs).to include('second')
    end
  end

  describe 'ActionController::Base.config.relative_url_root' do
    it 'returns the path prefix for a path-prefix site' do
      run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      conn.establish_connection(db: 'site_a')
      expect(ActionController::Base.config.relative_url_root).to eq('/site_a')
    end

    it 'returns nil for the default db with no default path prefix' do
      run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      conn.establish_connection(db: 'default')
      expect(ActionController::Base.config.relative_url_root).to be_nil
    end

    it 'reflects the correct prefix when switching between sites' do
      run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      conn.establish_connection(db: 'site_a')
      expect(ActionController::Base.config.relative_url_root).to eq('/site_a')
      conn.establish_connection(db: 'site_b')
      expect(ActionController::Base.config.relative_url_root).to eq('/site_b')
    end

    it 'returns the default path prefix when database.yml has path_prefix' do
      load_db_config('database_with_path_prefix.yml')
      run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      conn.establish_connection(db: 'default')
      expect(ActionController::Base.config.relative_url_root).to eq('/root')
    ensure
      load_db_config('database.yml')
    end

    it 'returns nil for a hostname-only site' do
      run_initializer(multisite_fixture: 'two_dbs.yml')
      conn.establish_connection(host: 'second.localhost')
      expect(ActionController::Base.config.relative_url_root).to be_nil
    end
  end

  describe 'Rails::Application.config.relative_url_root' do
    it 'returns the path prefix for a path-prefix site' do
      app = run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      conn.establish_connection(db: 'site_a')
      expect(app.config.relative_url_root).to eq('/site_a')
    end

    it 'returns nil for the default db with no default path prefix' do
      app = run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      conn.establish_connection(db: 'default')
      expect(app.config.relative_url_root).to be_nil
    end

    it 'reflects the correct prefix when switching between sites' do
      app = run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      conn.establish_connection(db: 'site_a')
      expect(app.config.relative_url_root).to eq('/site_a')
      conn.establish_connection(db: 'site_b')
      expect(app.config.relative_url_root).to eq('/site_b')
    end

    it 'returns the default path prefix when database.yml has path_prefix' do
      load_db_config('database_with_path_prefix.yml')
      app = run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      conn.establish_connection(db: 'default')
      expect(app.config.relative_url_root).to eq('/root')
    ensure
      load_db_config('database.yml')
    end

    it 'returns nil for a hostname-only site' do
      app = run_initializer(multisite_fixture: 'two_dbs.yml')
      conn.establish_connection(host: 'second.localhost')
      expect(app.config.relative_url_root).to be_nil
    end

    it 'returns the static prefix as a plain value when all sites share one prefix' do
      load_db_config('database_with_path_prefix.yml')
      app = run_initializer(multisite_fixture: 'two_dbs_same_path_prefix.yml')
      expect(app.config.relative_url_root).to eq('/root')
    ensure
      load_db_config('database.yml')
    end
  end

  describe 'static vs dynamic relative_url_root' do
    it 'sets relative_url_root as a plain string when all sites share one prefix' do
      load_db_config('database_with_path_prefix.yml')
      app = run_initializer(multisite_fixture: 'two_dbs_same_path_prefix.yml')
      expect(app.config.relative_url_root).to eq('/root')
      expect(ActionController::Base.config.singleton_class.method_defined?(:relative_url_root)).to eq(false)
    ensure
      load_db_config('database.yml')
    end

    it 'installs dynamic override when sites have different prefixes' do
      run_initializer(multisite_fixture: 'two_dbs_path_prefix.yml')
      expect(ActionController::Base.config.singleton_class.method_defined?(:relative_url_root)).to eq(true)
    end

    it 'sets no relative_url_root when no prefixes configured' do
      app = run_initializer(multisite_fixture: 'two_dbs.yml')
      expect(app.config.relative_url_root).to be_nil
      expect(ActionController::Base.config.singleton_class.method_defined?(:relative_url_root)).to eq(false)
    end
  end
end
