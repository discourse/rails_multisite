# frozen_string_literal: true
desc "generate multisite config file (if missing)"
task "multisite:generate:config" => :environment do
  filename = RailsMultisite::ConnectionManagement.config_filename

  if File.exist?(filename)
    puts "Config is already generated at #{RailsMultisite::ConnectionManagement::CONFIG_FILE}"
  else
    puts "Generated config file at #{RailsMultisite::ConnectionManagement::CONFIG_FILE}"
    File.open(filename, 'w') do |f|
      f.write <<-CONFIG
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

  end
end
