# frozen_string_literal: true
desc "generate multisite config file (if missing)"
task "multisite:generate:config" => :environment do
  filename = RailsMultisite::ConnectionManagement.config_filename
  if !filename && Rails.application.config.respond_to?(:multisite_config_path)
    filename = Rails.application.config.multisite_config_path.presence
  end
  filename ||= RailsMultisite::ConnectionManagement.default_config_filename

  if File.exist?(filename)
    puts "Config is already generated at #{filename}"
  else
    File.open(filename, 'w') do |f|
      f.write <<-CONFIG
{}

# site_name:
#   adapter: postgresql
#   database: db_name
#   host: localhost
#   pool: 5
#   timeout: 5000
#   host_names:
#     - www.mysite.com
#     - www.anothersite.com
CONFIG

    end
    puts "Generated config file at #{filename}"
  end
end
