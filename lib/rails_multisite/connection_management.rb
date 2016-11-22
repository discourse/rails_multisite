module RailsMultisite
  class ConnectionManagement
    CONFIG_FILE = 'config/multisite.yml'
    DEFAULT = 'default'.freeze
    SPEC_KLASS = ActiveRecord::ConnectionAdapters::ConnectionSpecification

    def self.has_db?(db)
      return true if db == DEFAULT
      (defined? @@db_spec_cache) && @@db_spec_cache && @@db_spec_cache[db]
    end

    def self.rails4?
      !!(Rails.version =~ /^4/)
    end

    def self.establish_connection(opts)
      opts[:db] = opts[:db].to_s

      if opts[:db] == DEFAULT && (!defined?(@@default_spec) || !@@default_spec)
        # don't do anything .. handled implicitly
      else
        spec = connection_spec(opts) || @@default_spec
        handler = nil
        if spec != @@default_spec
          handler = @@connection_handlers[spec]
          unless handler
            handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
            handler.establish_connection(ActiveRecord::Base, spec)
            @@connection_handlers[spec] = handler
          end
        else
          handler = @@default_connection_handler
          if !@@established_default
            handler.establish_connection(ActiveRecord::Base, spec)
            @@established_default = true
          end
        end

        ActiveRecord::Base.connection_handler = handler
      end
    end

    def self.with_hostname(hostname)

      unless defined? @@db_spec_cache
        # just fake it for non multisite
        yield hostname
        return
      end

      old = current_hostname
      connected = ActiveRecord::Base.connection_pool.connected?

      establish_connection(:host => hostname) unless connected && hostname == old
      rval = yield hostname

      unless connected && hostname == old
        ActiveRecord::Base.connection_handler.clear_active_connections!

        establish_connection(:host => old)
        ActiveRecord::Base.connection_handler.clear_active_connections! unless connected
      end

      rval
    end

    def self.with_connection(db = DEFAULT)
      old = current_db
      connected = ActiveRecord::Base.connection_pool.connected?

      establish_connection(:db => db) unless connected && db == old
      rval = yield db

      unless connected && db == old
        ActiveRecord::Base.connection_handler.clear_active_connections!

        establish_connection(:db => old)
        ActiveRecord::Base.connection_handler.clear_active_connections! unless connected
      end

      rval
    end

    def self.each_connection(opts=nil, &blk)

      old = current_db
      connected = ActiveRecord::Base.connection_pool.connected?

      queue = nil
      threads = nil

      if (opts && (threads = opts[:threads]))
        queue = Queue.new
        all_dbs.each{|db| queue << db}
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

              establish_connection(:db => db)
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
          establish_connection(:db => db)
          blk.call(db)
          ActiveRecord::Base.connection_handler.clear_active_connections!
        end
      end

      if errors && errors.length > 0
        raise StandardError, "Failed to run queries #{errors.inspect}"
      end


    ensure
      establish_connection(:db => old)
      ActiveRecord::Base.connection_handler.clear_active_connections! unless connected
    end

    def self.all_dbs
      [DEFAULT] +
        if defined?(@@db_spec_cache) && @@db_spec_cache
          @@db_spec_cache.keys.to_a
        else
          []
        end
    end

    def self.current_db
      ActiveRecord::Base.connection_pool.spec.config[:db_key] || DEFAULT
    end

    def self.config_filename=(config_filename)
      @@config_filename = config_filename
    end

    def self.config_filename
      @@config_filename ||= File.absolute_path(Rails.root.to_s + "/" + RailsMultisite::ConnectionManagement::CONFIG_FILE)
    end

    def self.current_hostname
      config = ActiveRecord::Base.connection_pool.spec.config
      config[:host_names].nil? ? config[:host] : config[:host_names].first
    end

    def self.clear_settings!
      @@db_spec_cache = nil
      @@host_spec_cache = nil
      @@default_spec = nil
    end

    def self.load_settings!
      configs = YAML::load(File.open(self.config_filename))
      verify_config(configs)
      resolver = SPEC_KLASS::Resolver.new(configs)
      @@db_spec_cache = Hash[*configs.map { |k, _| [k, resolver.spec(k.to_sym)] }.flatten]

      @@host_spec_cache = {}
      configs.each do |k,v|
        next unless v["host_names"]
        v["host_names"].each do |host|
          @@host_spec_cache[host] = @@db_spec_cache[k]
        end
      end

      @@default_spec = SPEC_KLASS::Resolver.new(ActiveRecord::Base.configurations).spec(Rails.env.to_sym)
      ActiveRecord::Base.configurations[Rails.env]["host_names"].each do |host|
        @@host_spec_cache[host] = @@default_spec
      end

      @@default_connection_handler = ActiveRecord::Base.connection_handler

      @@connection_handlers = {}
      @@established_default = false
    end

    def self.update_settings(configs)
      verify_config(configs)
      resolver = SPEC_KLASS::Resolver.new(configs)

      configs.each do |key, value|
        @@db_spec_cache.merge!("#{key}" => resolver.spec(key.to_sym) )

        next unless host_names = value["host_names"]
        db_spec = @@db_spec_cache[key]
        host_names.each { |host_name| @@host_spec_cache.merge!("#{host_name}" => db_spec) }
      end
    end

    def initialize(app, config = nil)
      @app = app
    end

    def self.host(env)
      request = Rack::Request.new(env)
      request['__ws'] || request.host
    end

    def call(env)
      host = self.class.host(env)
      begin

        #TODO: add a callback so users can simply go to a domain to register it, or something
        return [404, {}, ["not found"]] unless @@host_spec_cache[host]

        ActiveRecord::Base.connection_handler.clear_active_connections!
        self.class.establish_connection(:host => host)
        @app.call(env)
      ensure
        ActiveRecord::Base.connection_handler.clear_active_connections!
      end
    end

    def self.connection_spec(opts)
      if opts[:host]
        @@host_spec_cache[opts[:host]]
      else
        @@db_spec_cache[opts[:db]]
      end
    end

    private

    def self.verify_config(configs)
      no_prepared_statements = ActiveRecord::Base.configurations[Rails.env]["prepared_statements"] == false

      configs.each do |k,v|
        raise ArgumentError.new("Please do not name any db default!") if k == DEFAULT
        v[:db_key] = k
        v[:prepared_statements] = false if no_prepared_statements
      end
    end

  end
end
