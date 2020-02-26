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

        unless ConnectionManagement.connection_spec(host: host)
          db = @db_lookup && @db_lookup.call(env)
          if db
            host = nil
          else
            return [404, {}, ["not found"]]
          end
        end

        ActiveRecord::Base.connection_handler.clear_active_connections!
        ConnectionManagement.establish_connection(host: host, db: db)
        @app.call(env)
      ensure
        ActiveRecord::Base.connection_handler.clear_active_connections!
      end
    end
  end
end
