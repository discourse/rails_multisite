# frozen_string_literal: true
source 'https://rubygems.org'

def rails_master?
  ENV["RAILS_MASTER"] == '1'
end

if rails_master?
  gem 'arel', git: 'https://github.com/rails/arel.git'
  gem 'rails', git: 'https://github.com/rails/rails.git'
end

group :development, :test do
  gem 'byebug'
  gem 'rubocop'
  gem 'rubocop-discourse'
end

group :test do
  gem 'rspec'
  gem 'sqlite3'
end

group :development do
  gem 'guard'
  gem 'guard-rspec'
end

# Specify your gem's dependencies in rails_multisite.gemspec
gemspec
