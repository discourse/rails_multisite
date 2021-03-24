# frozen_string_literal: true
ENV["RAILS_ENV"] ||= 'test'
RSpec.configure do |config|
  config.order = 'random'

  require 'sqlite3'
  require 'byebug'
  require 'active_record'
  require 'active_record/base'

  class SQLite3::Database
    def self.query_log
      @@query_log ||= []
    end

    alias_method :old_execute, :execute
    alias_method :old_prepare, :prepare

    def execute(*args, &blk)
      self.class.query_log << [args, caller, Thread.current.object_id]
      old_execute(*args, &blk)
    end

    def prepare(*args, &blk)
      self.class.query_log << [args, caller, Thread.current.object_id]
      old_prepare(*args, &blk)
    end
  end

  def fixture_path(name)
    File.expand_path("fixtures/#{name}", File.dirname(__FILE__))
  end

  def load_db_config(name)
    if defined?(ActiveRecord::DatabaseConfigurations)
      configs = ActiveRecord::DatabaseConfigurations.new(YAML::load(File.open(fixture_path(name))))
      ActiveRecord::Base.configurations = configs
    else
      ActiveRecord::Base.configurations = YAML::load(File.open(fixture_path(name)))
    end
  end

  config.before(:suite) do
    load_db_config("database.yml")
  end
end
