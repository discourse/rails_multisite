## 5.0.0 - 2023-05-31

 * Add support for Rails 7.1+
 * Drop support for Ruby < 3.0
 * Drop support for Rails < 6.0

## 4.0.1 - 2022-01-13

 * Add support for Rails 7.0+

## 4.0.0 - 2021-11-15

 * Vary the encrypted/signed cookie salts per-hostname (fix for CVE-2021-41263). This update will
   cause existing cookies to be invalidated

## 3.1.0 - 2021-09-10

 * Make config file path configurable via `Rails.configuration.multisite_config_path`

## 3.0.0 - 2021-03-24

 * First version to support Rails 6.1 / 7
 * Removed support for Ruby 2.4 which is no longer maintained

## 2.4.0 - 2020-09-15

 * __ws parameter is only supported for RailsMultisite::ConnectionManagement.asset_hostname
   previously we would support this for any hostname and careful attackers could use this
   maliciously. Additionally, if __ws is used we will always strip request cookies as an
   extra security measure.

## 2.3.0 - 2020-06-10

 * Allow the default connection handler to be changed.

## 2.2.2 - 2020-06-02

 * Use `ActiveRecord::Base.connection_handlers` to keep track of all connection handlers.

## 2.1.2 - 2020-05-08

 * Add support for `Rails.configuration.skip_multisite_middleware`, if configured railstie will avoid
 all configuration of middleware.

## 2.1.1 - 2020-03-13

 * Add `current_db_hostnames` to get a listing of current db hostnames

## 2.1.0 - 2020-02-28

 * When reloading, only update changed connection specs. This means that ActiveRecord can keep the existing SchemaCache for unchanged connections
 * Remove support for Rails 4
 * Remove support for Ruby 2.3

## 2.0.7 - 2019-04-29

 * Add support for Rails 6
 * Remove support for Ruby 2.2 as it is EOL

## 2.0.6 - 2019-01-23

  * Fixed a bug where calling `RailsMultisite::ConnectionManagement#establish_connection`
    with a `db: default, raise_on_missing: true` would raise an error.

## 2.0.5 - YANKED

## 2.0.4 - 2018-02-12

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
