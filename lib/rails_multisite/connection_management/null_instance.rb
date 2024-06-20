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

      def establish_connection(_opts)
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

      def with_connection(db = DEFAULT, &blk)
        connected = ActiveRecord::Base.connection_pool.connected?
        result = blk.call(db)
        ActiveRecord::Base.connection_handler.clear_active_connections! unless connected
        result
      end

      def with_hostname(hostname, &blk)
        blk.call(hostname)
      end
    end
  end
end
