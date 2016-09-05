module RailsMultisite
  class Formatter < ::ActiveSupport::Logger::SimpleFormatter
    include ::ActiveSupport::TaggedLogging::Formatter

    def call(severity, timestamp, progname, msg)
      "[#{RailsMultisite::ConnectionManagement.current_db}] #{super}"
    end
  end
end
