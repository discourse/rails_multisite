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
  db_id: 1  # ensure db_id is unique for each site
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
  db_id: 2 # ensure db_id is unique for each site
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


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
