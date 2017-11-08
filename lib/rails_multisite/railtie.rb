# frozen_string_literal: true

module RailsMultisite
  class Railtie < Rails::Railtie
    rake_tasks do
      Dir[File.join(File.dirname(__FILE__), '../tasks/*.rake')].each { |f| load f }
    end

    initializer "RailsMultisite.init" do |app|
      Rails.configuration.multisite = false

      if File.exist?(ConnectionManagement.config_filename)
        Rails.configuration.multisite = true
        Rails.logger.formatter = RailsMultisite::Formatter.new
        ConnectionManagement.load_settings!
        app.middleware.insert_after(ActionDispatch::Executor, RailsMultisite::ConnectionManagement)
        app.middleware.delete(ActionDispatch::Executor)

        if ENV['RAILS_DB']
          ConnectionManagement.establish_connection(db: ENV['RAILS_DB'])
        end
      else
        ConnectionManagement.set_current_db
      end
    end
  end
end
