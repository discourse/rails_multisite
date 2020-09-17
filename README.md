# Rails Multisite

This gem provides multi-db support for Rails applications.

Using its middleware you can partition your app so each hostname has its own db.

It provides a series of helper for working with multiple database, and some additional rails tasks for working with them.

It was extracted from Discourse. https://discourse.org

## Installation

Add this line to your application's Gemfile:

    gem 'rails_multisite'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rails_multisite

## Usage

Configuration requires a file called: `config/multisite.yml` that specifies connection specs for all dbs.

```
mlp:
  adapter: postgresql
  database: discourse_mlp
  username: discourse_mlp
  password: applejack
  host: dbhost
  pool: 5
  timeout: 5000
  host_names:
    - discourse.equestria.com
    - discourse.equestria.internal

drwho:
  adapter: postgresql
  database: discourse_who
  username: discourse_who
  password: "Up the time stream without a TARDIS"
  host: dbhost
  pool: 5
  timeout: 5000
  host_names:
    - discuss.tardis.gallifrey
```


### Execute a query on each connection

```
RailsMultisite::ConnectionManagement.each_connection do |db|
  # run query in context of db
  # eg: User.find(1)
end
```

```
RailsMultisite::ConnectionManagement.each_connection(threads: 5) do |db|
  # run query in context of db, will do so in a thread pool of 5 threads
  # if any query fails an exception will be raised
  # eg: User.find(1)
end
```

### Usage with Rails

#### `RAILS_DB` Environment Variable

When working with a Rails application, you can specify the DB that you'll like to work with by specifying the `RAILS_DB` ENV variable.

```
# config/multisite.yml

db_one:
  adapter: ...
  database: some_database_1

db_two:
  adapater: ...
  database: some_database_2
```

To get a Rails console that is connected to `some_database_1` database:

```
RAILS_DB=db_one rails console
```

### CDN origin support

To avoid needing to configure many origins you can consider using `RailsMultisite::ConnectionManagement.asset_hostnames`

When configured, requests to `asset_hostname`?__ws=another.host.name will be re-routed to the correct site. Cookies will
be stripped on all incoming requests.

Example:

- Multisite serves `sub.example.com` and `assets.example.com`
- `RailsMultisite::ConnectionManagement.asset_hostnames = ['assets.example.com']`
- Requests to `https://assets.example.com/route/?__ws=sub.example.com` will be routed to the `sub.example.com`


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
