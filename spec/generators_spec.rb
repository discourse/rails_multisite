# frozen_string_literal: true

require "spec_helper"
require "rails_multisite"
require "rake"
require "tmpdir"

describe Rake::Task do
  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../lib/tasks/generators.rake", __dir__)
    Dir.mktmpdir do |dir|
      @filename = File.join(dir, "multisite.yml")
      example.run
    end
  ensure
    Rake.application = original_application
  end

  def generate
    Rake::Task["multisite:generate:config"].invoke
  end

  it "generates a loadable empty configuration at the default path" do
    allow(Rails).to receive(:application).and_return(double(config: Object.new))
    allow(RailsMultisite::ConnectionManagement).to receive(:config_filename).and_return(nil)
    allow(RailsMultisite::ConnectionManagement).to receive(:default_config_filename).and_return(@filename)

    expect { generate }.to output("Generated config file at #{@filename}\n").to_stdout
    expect(YAML.safe_load_file(@filename)).to eq({})
  end

  it "uses a custom path before its configuration exists" do
    allow(Rails).to receive(:application).and_return(double(config: double(multisite_config_path: @filename)))
    allow(RailsMultisite::ConnectionManagement).to receive(:config_filename).and_return(nil)

    expect { generate }.to output("Generated config file at #{@filename}\n").to_stdout
    expect(YAML.safe_load_file(@filename)).to eq({})
  end

  it "leaves an existing configuration unchanged" do
    File.write(@filename, "second: {}\n")
    allow(RailsMultisite::ConnectionManagement).to receive(:config_filename).and_return(@filename)

    expect { generate }.to output("Config is already generated at #{@filename}\n").to_stdout
    expect(File.read(@filename)).to eq("second: {}\n")
  end
end
