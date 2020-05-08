# frozen_string_literal: true

module RailsMultisite
  class Railtie < Rails::Railtie
    rake_tasks do
      Dir[File.join(File.dirname(__FILE__), '../tasks/*.rake')].each { |f| load f }
    end

    initializer "RailsMultisite.init" do |app|
      app.config.multisite = false

      config_file = ConnectionManagement.default_config_filename
      if File.exist?(config_file)
        ConnectionManagement.config_filename = ConnectionManagement.default_config_filename
        app.config.multisite = true
        Rails.logger.formatter = RailsMultisite::Formatter.new

        if !skip_middleware?(app.config)
          app.middleware.insert_after(ActionDispatch::Executor, RailsMultisite::Middleware)
          app.middleware.delete(ActionDispatch::Executor)
        end

        if ENV['RAILS_DB'].present?
          ConnectionManagement.establish_connection(db: ENV['RAILS_DB'], raise_on_missing: true)
        end
      end
    end

    def skip_middleware?(config)
      return false if !config.respond_to?(:skip_multisite_middleware)
      config.skip_multisite_middleware
    end
  end
end
