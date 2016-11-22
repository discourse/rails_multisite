require 'spec_helper'
require 'rails_multisite'

class Person < ActiveRecord::Base; end

describe RailsMultisite::ConnectionManagement do

  after do
    conn.clear_settings!
  end

  let(:conn){ RailsMultisite::ConnectionManagement }

  def with_connection(db)
    conn.establish_connection(db: db)
    yield ActiveRecord::Base.connection.raw_connection
  ensure
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end

  context 'default' do

    it 'has correct all_dbs' do
      expect(conn.all_dbs).to eq(['default'])
    end

    context 'current' do
      before do
        conn.establish_connection(db: 'default')
        ActiveRecord::Base.establish_connection
      end

      it "has default current db" do
        expect(conn.current_db).to eq('default')
      end

      it "has current hostname" do
        expect(conn.current_hostname).to eq('default.localhost')
      end

    end

  end

  it "inherits prepared_statements" do
    ActiveRecord::Base.configurations[Rails.env]["prepared_statements"] = false
    conn.config_filename = "spec/fixtures/two_dbs.yml"
    conn.load_settings!

    expect(conn.connection_spec(db: "second").config[:prepared_statements]).to be(false)

    ActiveRecord::Base.configurations[Rails.env]["prepared_statements"] = nil
  end

  context 'two dbs' do

    before do
      conn.config_filename = "spec/fixtures/two_dbs.yml"
      conn.load_settings!
    end

    it 'accepts a symbol for the db name' do
      with_connection(:second) do
        expect(conn.current_db).to eq('second')
      end
    end

    it "can exectue a queries concurrently per db" do
      threads = Set.new
      conn.each_connection(threads: 2) do
        sleep 0.001
        threads << Thread.current.object_id
      end

      expect(threads.length).to eq(2)
    end

    it "correctly handles exceptions in threads mode" do

      begin
        conn.each_connection(threads: 2) do
          boom
        end
      rescue => e
        exp = e
      end

      expect(exp.to_s).to include("boom")
    end

    it "has correct all_dbs" do
      expect(conn.all_dbs).to eq(['default', 'second'])
    end

    context 'second db' do
      before do
        conn.establish_connection(db: 'second')
      end

      it "is configured correctly" do
        expect(conn.current_db).to eq('second')
        expect(conn.current_hostname).to eq("second.localhost")
      end
    end

    context 'data partitioning' do
      after do
        ['default','second'].each do |db|
          with_connection(db) do |cnn|
            cnn.execute("drop table people") rescue nil
          end
        end
      end

      it 'partitions data correctly' do

        ['default','second'].map do |db|

          with_connection(db) do |cnn|
            cnn.execute("create table if not exists people(id INTEGER PRIMARY KEY AUTOINCREMENT, db)")
          end
        end

        SQLite3::Database.query_log.clear

        5.times do
          ['default','second'].map do |db|
            Thread.new do
              with_connection(db) do |cnn|
                Person.create!(db: db)
              end
            end
          end.map(&:join)
        end

        lists = []
        ['default', 'second'].each do |db|
          with_connection(db) do |cnn|
            lists << Person.order(:id).to_a.map{|p| [p.id, p.db]}
          end
        end

        expect(lists[1]).to eq((1..5).map{|id| [id, "second"]})
        expect(lists[0]).to eq((1..5).map{|id| [id, "default"]})

      end
    end
  end

  context "updating settings" do
    before do
      conn.config_filename = "spec/fixtures/two_dbs.yml"
      conn.load_settings!
    end

    it 'should load the new settings correctly' do
      hostnames = ['cat.localhost', 'dog.localhost']

      conn.update_settings("apple" => {
        "adapter" => 'sqlite3', "host_names" => hostnames, "database" => 'tmp/db.test'
      })

      [{ db: 'apple' }, { host: 'cat.localhost' }].each do |opts|
        expect(conn.connection_spec(opts).config[:host_names]).to eq(hostnames)
      end

      expect(conn.all_dbs).to eq(['default', 'second', 'apple'])

      conn.establish_connection(db: 'apple')
      expect(conn.current_db).to eq('apple')
      expect(conn.current_hostname).to eq(hostnames[0])
      conn.with_hostname(hostnames[1]) { expect(conn.current_db).to eq('apple') }
    end
  end

end
