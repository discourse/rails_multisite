# frozen_string_literal: true
module RailsMultisite
  class Middleware
    def initialize(app, config = nil)
      @app = app
      @db_lookup = config && config[:db_lookup]
    end

    def call(env)
      host = ConnectionManagement.host(env)
      db = nil
      begin
        spec = ConnectionManagement.connection_spec(host: host, path: env["PATH_INFO"])

        unless spec
          db = @db_lookup && @db_lookup.call(env)
          if db
            host = nil
          else
            return [404, {}, ["not found"]]
          end
        end

        matched_prefix = spec&.config&.fetch(:path_prefix, nil) ||
          (spec && !spec.config[:db_key] ? ConnectionManagement.default_path_prefix : nil)

        if matched_prefix
          path_info = env["PATH_INFO"].to_s
          env["SCRIPT_NAME"] = env["SCRIPT_NAME"].to_s + matched_prefix
          env["PATH_INFO"] = path_info[matched_prefix.length..]
          env["PATH_INFO"] = "/" if env["PATH_INFO"].nil? || env["PATH_INFO"].empty?
          if spec.config[:db_key]
            db = spec.config[:db_key]
            host = nil
          end
        end

        ActiveRecord::Base.connection_handler.clear_active_connections!
        ConnectionManagement.establish_connection(host: host, db: db)
        CookieSalt.update_cookie_salts(env: env, host: host)
        @app.call(env)
      ensure
        ActiveRecord::Base.connection_handler.clear_active_connections!
      end
    end
  end
end
