# frozen_string_literal: true

module RailsMultisite
  class ConnectionManagement
    class NullInstance
      include Singleton

      def clear_settings!
      end

      def config_filename
      end

      def default_connection_handler=(_connection_handler)
      end

      def establish_connection(db: nil, host: nil, raise_on_missing: true)
      end

      def reload
      end

      def all_dbs
        [DEFAULT]
      end

      def connection_spec(_opts)
        ConnectionSpecification.current
      end

      def current_db
        DEFAULT
      end

      def each_connection(_opts = nil, &blk)
        with_connection(&blk)
      end

      def has_db?(db)
        db == DEFAULT
      end

      def host(env)
        env["HTTP_HOST"]
      end

      def with_connection(db = DEFAULT, raise_on_missing: true, &blk)
        raise UnknownSiteError.new(db) if !has_db?(db) && raise_on_missing

        connected = ActiveRecord::Base.connection_pool.connected?
        result = blk.call(db)
        if !connected
          ActiveRecord::Base.connection_handler.clear_active_connections!
        end
        result
      end

      def with_hostname(hostname, raise_on_missing: true, &blk)
        blk.call(hostname)
      end
    end
  end
end
