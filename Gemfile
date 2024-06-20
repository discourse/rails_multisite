# frozen_string_literal: true
source 'https://rubygems.org'

def rails_master?
  ENV["RAILS_MASTER"] == '1'
end

if rails_master?
  gem 'arel', git: 'https://github.com/rails/arel.git'
  gem 'rails', git: 'https://github.com/rails/rails.git', branch: 'main'
end

# Specify your gem's dependencies in rails_multisite.gemspec
gemspec
