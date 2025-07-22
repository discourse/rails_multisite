# frozen_string_literal: true

module RailsMultisite
  class ConnectionManagement
    class ConnectionSpecification
      class << self
        def current
          new(ActiveRecord::Base.connection_pool.db_config)
        end

        def db_spec_cache(configs)
          resolve_configs = ActiveRecord::DatabaseConfigurations.new(configs)
          configs.map { |k, _| [k, new(resolve_configs.resolve(k.to_sym))] }.to_h
        end

        def default
          new(ActiveRecord::Base.configurations.resolve(Rails.env.to_sym))
        end
      end

      attr_reader :spec

      def initialize(spec)
        @spec = spec
      end

      def name
        spec.env_name
      end

      def to_hash
        spec.configuration_hash
      end
      alias config to_hash
    end
  end
end
