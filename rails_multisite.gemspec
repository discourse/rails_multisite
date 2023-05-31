# frozen_string_literal: true
# -*- encoding: utf-8 -*-
require File.expand_path('../lib/rails_multisite/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Sam Saffron"]
  gem.email         = ["sam.saffron@gmail.com"]
  gem.description   = %q{Multi tenancy support for Rails}
  gem.summary       = %q{Multi tenancy support for Rails}
  gem.homepage      = ""

  # when this is extracted comment it back in, prd has no .git
  # gem.files         = `git ls-files`.split($\)
  gem.files         = Dir['README*', 'LICENSE', 'lib/**/*.rb', 'lib/**/*.rake']

  gem.name          = "rails_multisite"
  gem.require_paths = ["lib"]
  gem.version       = RailsMultisite::VERSION

  gem.required_ruby_version = ">=3.0.0"

  gem.add_dependency "activerecord", ">= 6.0"
  gem.add_dependency "railties", ">= 6.0"
end
