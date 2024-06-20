# frozen_string_literal: true

module RailsMultisite
  class ConnectionManagement
    class ConnectionSpecification
      class << self
        def current
          ActiveRecord::Base.connection_pool.spec
        end

        def db_spec_cache(configs)
          resolve_configs = configs
          # rails 6 needs to use a proper object for the resolver
          if defined?(ActiveRecord::DatabaseConfigurations)
            resolve_configs = ActiveRecord::DatabaseConfigurations.new(configs)
          end
          resolver =
            ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(resolve_configs)
          configs.map { |k, _| [k, resolver.spec(k.to_sym)] }.to_h
        end

        def default
          ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(
            ActiveRecord::Base.configurations,
          ).spec(Rails.env.to_sym)
        end
      end
    end
  end
end
