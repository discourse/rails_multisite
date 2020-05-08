## 2.1.2 - 08-05-2020

 * Add support for `Rails.configuration.skip_multisite_middleware`, if configured railstie will avoid
 all configuration of middleware.

## 2.1.1 - 13-03-2020

 * Add `current_db_hostnames` to get a listing of current db hostnames

## 2.1.0 - 28-02-2020

 * When reloading, only update changed connection specs. This means that ActiveRecord can keep the existing SchemaCache for unchanged connections
 * Remove support for Rails 4
 * Remove support for Ruby 2.3

## 2.0.7 - 29-04-2019

 * Add support for Rails 6
 * Remove support for Ruby 2.2 as it is EOL

## 2.0.6 - 23-01-2019

  * Fixed a bug where calling `RailsMultisite::ConnectionManagement#establish_connection`
    with a `db: default, raise_on_missing: true` would raise an error.

## 2.0.5 - YANKED

## 2.0.4 - 12-02-2018

  * Fix bug where calling `RailsMultisite::ConnectionManagement.current_hostname`
    with a `default` connection would throw an undefined method error.

## 2.0.3 - yanked

  * Base `RailsMultisite::ConnectionManagement.current_hostname` on `@host_spec_cache`.

## 2.0.2

  * with_connection should return result of block

## 1.1.2

  * raise error if RAILS_DB is specified yet missing

## 1.1.1

  * allows db_lookup callback for middleware, this allows you to whitelist paths in multisite

## 1.0.6

  * Revert deprecation fix because it can break multisite in subtle ways.
  * Allow `db` to be passed as a symbol to `RailsMultisite::ConnectionManagement.establish_connection`.

## 1.0.5

  * Fix deprecation warnings.
