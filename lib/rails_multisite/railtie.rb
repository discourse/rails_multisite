# frozen_string_literal: true

module RailsMultisite
  class Railtie < Rails::Railtie
    rake_tasks do
      Dir[File.join(File.dirname(__FILE__), '../tasks/*.rake')].each { |f| load f }
    end

    initializer "RailsMultisite.init" do |app|
      Rails.configuration.multisite = false

      config_file = ConnectionManagement.default_config_filename
      if File.exist?(config_file)
        ConnectionManagement.config_filename = ConnectionManagement.default_config_filename
        Rails.configuration.multisite = true
        Rails.logger.formatter = RailsMultisite::Formatter.new
        app.middleware.insert_after(ActionDispatch::Executor, RailsMultisite::Middleware)
        app.middleware.delete(ActionDispatch::Executor)

        if ENV['RAILS_DB'].present?
          ConnectionManagement.establish_connection(db: ENV['RAILS_DB'], raise_on_missing: true)
        end
      else
        ConnectionManagement.set_current_db
      end
    end
  end
end
