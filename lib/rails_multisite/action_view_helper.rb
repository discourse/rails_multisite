# frozen_string_literal: true

module RailsMultisite
  module ActionViewHelper
    def config=(value)
      value.define_singleton_method(:relative_url_root) do
        RailsMultisite::ConnectionManagement.current_path_prefix
      end

      super(value)
    end
  end
end
