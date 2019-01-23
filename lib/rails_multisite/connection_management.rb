# frozen_string_literal: true
#
module RailsMultisite
  class ConnectionManagement

    DEFAULT = 'default'

    def self.default_config_filename
      File.absolute_path(Rails.root.to_s + "/config/multisite.yml")
    end

    def self.clear_settings!
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

    def self.config_filename
      @instance.config_filename
    end

    def self.reload
      @instance = new(instance.config_filename)
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
      spec = @instance.connection_spec(db: self.current_db) if @instance
      spec ||= ActiveRecord::Base.connection_pool.spec
      config = spec.config
      config[:host_names].nil? ? config[:host] : config[:host_names].first
    end

    def self.connection_spec(opts)
      if @instance
        @instance.connection_spec(opts)
      else
        ActiveRecord::Base.connection_pool.spec
      end
    end

    def self.host(env)
      if @instance
        @instance.host(env)
      else
        env["HTTP_HOST"]
      end
    end

    attr_reader :config_filename

    def initialize(config_filename)
      @config_filename = config_filename

      spec_klass = ActiveRecord::ConnectionAdapters::ConnectionSpecification
      configs = YAML::load(File.open(@config_filename))

      no_prepared_statements = ActiveRecord::Base.configurations[Rails.env]["prepared_statements"] == false

      configs.each do |k, v|
        raise ArgumentError.new("Please do not name any db default!") if k == DEFAULT
        v[:db_key] = k
        v[:prepared_statements] = false if no_prepared_statements
      end

      resolver = spec_klass::Resolver.new(configs)
      @db_spec_cache = Hash[*configs.map { |k, _| [k, resolver.spec(k.to_sym)] }.flatten]

      @host_spec_cache = {}

      configs.each do |k, v|
        next unless v["host_names"]
        v["host_names"].each do |host|
          @host_spec_cache[host] = @db_spec_cache[k]
        end
      end

      @default_spec = spec_klass::Resolver.new(ActiveRecord::Base.configurations).spec(Rails.env.to_sym)
      ActiveRecord::Base.configurations[Rails.env]["host_names"].each do |host|
        @host_spec_cache[host] = @default_spec
      end

      @default_connection_handler = ActiveRecord::Base.connection_handler

      @connection_handlers = {}
      @established_default = false
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
        handler = @connection_handlers[spec]
        unless handler
          handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
          handler_establish_connection(handler, spec)
          @connection_handlers[spec] = handler
        end
      else
        handler = @default_connection_handler
        if !@established_default
          handler_establish_connection(handler, spec)
          @established_default = true
        end
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
      ActiveRecord::Base.connection_pool.spec.config[:db_key] || DEFAULT
    end

    def current_hostname
      ConnectionManagement.current_hostname
    end

    def host(env)
      if host = env["RAILS_MULTISITE_HOST"]
        return host
      end

      request = Rack::Request.new(env)
      host = request['__ws'] || request.host

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
      if Rails::VERSION::MAJOR >= 5
        handler.establish_connection(spec.config)
      else
        handler.establish_connection(ActiveRecord::Base, spec)
      end
    end

  end
end
