# frozen_string_literal: true

module RailsMultisite
  class Railtie < Rails::Railtie
    rake_tasks do
      Dir[File.join(File.dirname(__FILE__), '../tasks/*.rake')].each { |f| load f }
    end

    initializer "RailsMultisite.init" do |app|
      app.config.multisite = false

      config_file =
        app.config.respond_to?(:multisite_config_path) &&
        app.config.multisite_config_path.presence

      config_file ||= ConnectionManagement.default_config_filename

      if File.exist?(config_file)
        ConnectionManagement.config_filename = config_file
        app.config.multisite = true
        Rails.logger.formatter = RailsMultisite::Formatter.new if Rails.logger

        if !RailsMultisite::Railtie.skip_middleware?(app.config)
          app.middleware.insert_after(ActionDispatch::Executor, RailsMultisite::Middleware)
          app.middleware.delete(ActionDispatch::Executor)
        end

        prefix = ConnectionManagement.static_path_prefix
        if !ConnectionManagement.dynamic_path_prefix_enabled? && prefix && prefix != "/"
          # TODO: sanity check this. Is relative_url_root even configurable here?
          # Wasn't the whole point of overriding individual framework methods bec the config is already set?
          app.config.relative_url_root = prefix
        elsif ConnectionManagement.dynamic_path_prefix_enabled?
          app.config.define_singleton_method(:relative_url_root) do
            RailsMultisite::ConnectionManagement.current_path_prefix
          end

          ActiveSupport.on_load(:action_controller_base) do
            self.config.define_singleton_method(:relative_url_root) do
              RailsMultisite::ConnectionManagement.current_path_prefix
            end
          end

          ActiveSupport.on_load(:action_view) do
            prepend RailsMultisite::ActionViewHelper
          end

          ActiveSupport.on_load(:action_mailer) do
            self.config.define_singleton_method(:relative_url_root) do
              RailsMultisite::ConnectionManagement.current_path_prefix
            end
          end
        end

        if ENV['RAILS_DB'].present?
          ConnectionManagement.establish_connection(db: ENV['RAILS_DB'], raise_on_missing: true)
        end
      end
    end

    def self.skip_middleware?(config)
      return false if !config.respond_to?(:skip_multisite_middleware)
      config.skip_multisite_middleware
    end
  end
end
