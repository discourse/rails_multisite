module RailsMultisite
  class Formatter < ::ActiveSupport::Logger::SimpleFormatter
    def call(severity, timestamp, progname, msg)
      "[#{RailsMultisite::ConnectionManagement.current_db}] #{super}"
    end
  end
end
