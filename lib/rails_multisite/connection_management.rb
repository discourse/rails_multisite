# frozen_string_literal: true

if Rails.version >= '6.1'
  require 'rails_multisite/connection_management/rails_61_compat'
else
  require 'rails_multisite/connection_management/rails_60_compat'
end

module RailsMultisite
  class ConnectionManagement
    DEFAULT = 'default'

    def self.default_config_filename
      File.absolute_path(Rails.root.to_s + "/config/multisite.yml")
    end

    def self.clear_settings!
      @instance&.db_spec_cache&.each do |key, spec|
        @instance.connection_handlers.delete(self.handler_key(spec))
      end

      @instance = nil
    end

    def self.load_settings!
      # no op only here backwards compat
      STDERR.puts "RailsMultisite::ConnectionManagement.load_settings! is deprecated"
    end

    def self.instance
      @instance
    end

    def self.config_filename=(config_filename)
      if config_filename.nil?
        @instance = nil
      else
        @instance = new(config_filename)
      end
    end

    def self.asset_hostnames
      @asset_hostnames
    end

    def self.asset_hostnames=(h)
      @asset_hostnames = h
    end

    def self.config_filename
      @instance.config_filename
    end

    def self.reload
      @instance.reload
    end

    def self.has_db?(db)
      return true if db == DEFAULT
      !!(@instance && @instance.has_db?(db))
    end

    def self.establish_connection(opts)
      @instance.establish_connection(opts) if @instance
    end

    def self.with_hostname(hostname, &blk)
      if @instance
        @instance.with_hostname(hostname, &blk)
      else
        blk.call hostname
      end
    end

    def self.with_connection(db = DEFAULT, &blk)
      if @instance
        @instance.with_connection(db, &blk)
      else
        connected = ActiveRecord::Base.connection_pool.connected?
        result = blk.call db
        ActiveRecord::Base.clear_active_connections! unless connected
        result
      end
    end

    def self.each_connection(opts = nil, &blk)
      if @instance
        @instance.each_connection(opts, &blk)
      else
        with_connection(&blk)
      end
    end

    def self.all_dbs
      if @instance
        @instance.all_dbs
      else
        [DEFAULT]
      end
    end

    def self.current_db
      if @instance
        instance.current_db
      else
        DEFAULT
      end
    end

    def self.current_hostname
      current_db_hostnames.first
    end

    def self.current_db_hostnames
      config = (@instance&.connection_spec(db: current_db) || ConnectionSpecification.current).config
      config[:host_names].nil? ? [config[:host]] : config[:host_names]
    end

    def self.connection_spec(opts)
      if @instance
        @instance.connection_spec(opts)
      else
        ConnectionSpecification.current
      end
    end

    def self.host(env)
      if @instance
        @instance.host(env)
      else
        env["HTTP_HOST"]
      end
    end

    def self.handler_key(spec)
      @handler_key_suffix ||= begin
        if ActiveRecord::Base.respond_to?(:writing_role)
          "_#{ActiveRecord::Base.writing_role}"
        else
          ""
        end
      end

      :"#{spec.name}#{@handler_key_suffix}"
    end

    def self.default_connection_handler=(connection_handler)
      if @instance
        unless connection_handler.is_a?(ActiveRecord::ConnectionAdapters::ConnectionHandler)
          raise ArgumentError.new("Invalid connection handler")
        end

        @instance.default_connection_handler = connection_handler
      end
    end

    attr_reader :config_filename, :db_spec_cache, :connection_handlers
    attr_writer :default_connection_handler

    def initialize(config_filename)
      @config_filename = config_filename

      @connection_handlers = begin
        if ActiveRecord::Base.respond_to?(:connection_handlers)
          ActiveRecord::Base.connection_handlers
        else
          {}
        end
      end

      @db_spec_cache = {}
      @default_spec = ConnectionSpecification.default
      @default_connection_handler = ActiveRecord::Base.connection_handler

      @reload_mutex = Mutex.new

      load_config!
    end

    def load_config!
      configs = YAML::load(File.open(@config_filename))

      no_prepared_statements = @default_spec.config[:prepared_statements] == false

      configs.each do |k, v|
        raise ArgumentError.new("Please do not name any db default!") if k == DEFAULT
        v[:db_key] = k
        v[:prepared_statements] = false if no_prepared_statements
      end

      # Build a hash of db name => spec
      new_db_spec_cache = ConnectionSpecification.db_spec_cache(configs)
      new_db_spec_cache.each do |k, v|
        # If spec already existed, use the old version
        if v&.to_hash == @db_spec_cache[k]&.to_hash
          new_db_spec_cache[k] = @db_spec_cache[k]
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

      removed_dbs = @db_spec_cache.keys - new_db_spec_cache.keys
      removed_specs = @db_spec_cache.values_at(*removed_dbs)

      @host_spec_cache = new_host_spec_cache
      @db_spec_cache = new_db_spec_cache

      # Clean up connection handler cache.
      removed_specs.each { |s| @connection_handlers.delete(handler_key(s)) }
    end

    def reload
      @reload_mutex.synchronize do
        load_config!
      end
    end

    def has_db?(db)
      return true if db == DEFAULT
      @db_spec_cache[db]
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
        handler = @connection_handlers[handler_key(spec)]
        unless handler
          handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
          handler_establish_connection(handler, spec)
          @connection_handlers[handler_key(spec)] = handler
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
        ActiveRecord::Base.connection_handler.clear_active_connections! unless connected
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
        ActiveRecord::Base.connection_handler.clear_active_connections! unless connected
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
        threads.times.map do
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
        end.map(&:join)
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
      ActiveRecord::Base.connection_handler.clear_active_connections! unless connected
    end

    def all_dbs
      [DEFAULT] + @db_spec_cache.keys.to_a
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
        if request['__ws'] && self.class.asset_hostnames&.include?(request.host)
          request.cookies.clear
          request['__ws']
        else
          request.host
        end

      env["RAILS_MULTISITE_HOST"] = host
    end

    def connection_spec(opts)
      if opts[:host]
        @host_spec_cache[opts[:host]]
      else
        @db_spec_cache[opts[:db]]
      end
    end

    private

    def handler_establish_connection(handler, spec)
      handler.establish_connection(spec.config)
    end

    def handler_key(spec)
      self.class.handler_key(spec)
    end

  end
end
