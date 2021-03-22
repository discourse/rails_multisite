# frozen_string_literal: true

if Rails.version >= "6.1"
  require "rails_multisite/connection_management/rails_61_compat"
else
  require "rails_multisite/connection_management/rails_60_compat"
end
require "rails_multisite/connection_management/null_instance"

module RailsMultisite
  class ConnectionManagement
    DEFAULT = "default"

    cattr_accessor :connection_handlers, default: {}

    attr_reader :config_filename, :db_spec_cache

    class << self
      attr_accessor :asset_hostnames

      delegate :all_dbs,
               :config_filename,
               :connection_spec,
               :current_db,
               :default_connection_handler=,
               :each_connection,
               :establish_connection,
               :has_db?,
               :host,
               :reload,
               :with_connection,
               :with_hostname,
               to: :instance

      def default_config_filename
        File.absolute_path(Rails.root.to_s + "/config/multisite.yml")
      end

      def clear_settings!
        instance.clear_settings!
        @instance = nil
      end

      def load_settings!
        # no op only here backwards compat
        STDERR.puts "RailsMultisite::ConnectionManagement.load_settings! is deprecated"
      end

      def instance
        @instance || NullInstance.instance
      end

      def config_filename=(config_filename)
        if config_filename.blank?
          @instance = nil
        else
          @instance = new(config_filename)
        end
      end

      def current_hostname
        current_db_hostnames.first
      end

      def current_db_hostnames
        config =
          (
            connection_spec(db: current_db) || ConnectionSpecification.current
          ).config
        config[:host_names] || [config[:host]]
      end

      def handler_key(spec)
        @handler_key_suffix ||=
          begin
            if ActiveRecord.respond_to?(:writing_role)
              "_#{ActiveRecord.writing_role}"
            elsif ActiveRecord::Base.respond_to?(:writing_role)
              "_#{ActiveRecord::Base.writing_role}"
            else
              ""
            end
          end

        :"#{spec.name}#{@handler_key_suffix}"
      end
    end

    def initialize(config_filename)
      @config_filename = config_filename

      @db_spec_cache = {}
      @default_spec = ConnectionSpecification.default
      @default_connection_handler = ActiveRecord::Base.connection_handler

      @reload_mutex = Mutex.new

      load_config!
    end

    def load_config!
      configs = YAML.safe_load(File.open(config_filename))

      no_prepared_statements =
        @default_spec.config[:prepared_statements] == false

      configs.each do |k, v|
        if k == DEFAULT
          raise ArgumentError.new("Please do not name any db default!")
        end
        v[:db_key] = k
        v[:prepared_statements] = false if no_prepared_statements
      end

      # Build a hash of db name => spec
      new_db_spec_cache = ConnectionSpecification.db_spec_cache(configs)
      new_db_spec_cache.each do |k, v|
        # If spec already existed, use the old version
        if v&.to_hash == db_spec_cache[k]&.to_hash
          new_db_spec_cache[k] = db_spec_cache[k]
        end
      end

      # Build a hash of hostname => spec
      new_host_spec_cache = {}
      configs.each do |k, v|
        next unless v["host_names"]
        v["host_names"].each do |host|
          new_host_spec_cache[host] = new_db_spec_cache[k]
        end
      end

      # Add the default hostnames as well
      @default_spec.config[:host_names].each do |host|
        new_host_spec_cache[host] = @default_spec
      end

      removed_dbs = db_spec_cache.keys - new_db_spec_cache.keys
      removed_specs = db_spec_cache.values_at(*removed_dbs)

      @host_spec_cache = new_host_spec_cache
      @db_spec_cache = new_db_spec_cache

      # Clean up connection handler cache.
      removed_specs.each { |s| connection_handlers.delete(handler_key(s)) }
    end

    def reload
      @reload_mutex.synchronize { load_config! }
    end

    def has_db?(db)
      db == DEFAULT || !!db_spec_cache[db]
    end

    def establish_connection(opts)
      opts[:db] = opts[:db].to_s

      if opts[:db] != DEFAULT
        spec = connection_spec(opts)

        if (!spec && opts[:raise_on_missing])
          raise "ERROR: #{opts[:db]} not found!"
        end
      end

      spec ||= @default_spec
      handler = nil
      if spec != @default_spec
        handler = connection_handlers[handler_key(spec)]
        unless handler
          handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
          handler.establish_connection(spec.config)
          connection_handlers[handler_key(spec)] = handler
        end
      else
        handler = @default_connection_handler
      end

      ActiveRecord::Base.connection_handler = handler
    end

    def with_hostname(hostname)
      old = current_hostname
      connected = ActiveRecord::Base.connection_pool.connected?

      establish_connection(host: hostname) unless connected && hostname == old
      rval = yield hostname

      unless connected && hostname == old
        ActiveRecord::Base.connection_handler.clear_active_connections!

        establish_connection(host: old)
        unless connected
          ActiveRecord::Base.connection_handler.clear_active_connections!
        end
      end

      rval
    end

    def with_connection(db = DEFAULT)
      old = current_db
      connected = ActiveRecord::Base.connection_pool.connected?

      establish_connection(db: db) unless connected && db == old
      rval = yield db

      unless connected && db == old
        ActiveRecord::Base.connection_handler.clear_active_connections!

        establish_connection(db: old)
        unless connected
          ActiveRecord::Base.connection_handler.clear_active_connections!
        end
      end

      rval
    end

    def each_connection(opts = nil, &blk)
      old = current_db
      connected = ActiveRecord::Base.connection_pool.connected?

      queue = nil
      threads = nil

      if (opts && (threads = opts[:threads]))
        queue = Queue.new
        all_dbs.each { |db| queue << db }
      end

      errors = nil

      if queue
        threads
          .times
          .map do
            Thread.new do
              while true
                begin
                  db = queue.deq(true)
                rescue ThreadError
                  db = nil
                end

                break unless db

                establish_connection(db: db)
                # no choice but to rescue, should probably log

                begin
                  blk.call(db)
                rescue => e
                  (errors ||= []) << e
                end
                ActiveRecord::Base.connection_handler.clear_active_connections!
              end
            end
          end
          .map(&:join)
      else
        all_dbs.each do |db|
          establish_connection(db: db)
          blk.call(db)
          ActiveRecord::Base.connection_handler.clear_active_connections!
        end
      end

      if errors && errors.length > 0
        raise StandardError, "Failed to run queries #{errors.inspect}"
      end
    ensure
      establish_connection(db: old)
      unless connected
        ActiveRecord::Base.connection_handler.clear_active_connections!
      end
    end

    def all_dbs
      [DEFAULT] + db_spec_cache.keys.to_a
    end

    def current_db
      ConnectionSpecification.current.config[:db_key] || DEFAULT
    end

    def current_hostname
      ConnectionManagement.current_hostname
    end

    def host(env)
      if host = env["RAILS_MULTISITE_HOST"]
        return host
      end

      request = Rack::Request.new(env)

      host =
        if request["__ws"] && self.class.asset_hostnames&.include?(request.host)
          request.cookies.clear
          request["__ws"]
        else
          request.host
        end

      env["RAILS_MULTISITE_HOST"] = host
    end

    def connection_spec(opts)
      opts[:host] ? @host_spec_cache[opts[:host]] : db_spec_cache[opts[:db]]
    end

    def clear_settings!
      db_spec_cache.each do |key, spec|
        connection_handlers.delete(handler_key(spec))
      end
    end

    def default_connection_handler=(connection_handler)
      unless connection_handler.is_a?(
               ActiveRecord::ConnectionAdapters::ConnectionHandler
             )
        raise ArgumentError.new("Invalid connection handler")
      end

      @default_connection_handler = connection_handler
    end

    private

    def handler_key(spec)
      self.class.handler_key(spec)
    end
  end
end
