# frozen_string_literal: true
require 'spec_helper'
require 'rails_multisite'

class Person < ActiveRecord::Base; end

describe RailsMultisite::ConnectionManagement do

  let(:conn) { RailsMultisite::ConnectionManagement }

  before do
    ActiveRecord::Base.establish_connection
  end

  after do
    conn.clear_settings!
    ActiveRecord::Base.remove_connection
  end

  def with_connection(db)
    original_connection_handler = ActiveRecord::Base.connection_handler
    original_connection_handler.clear_active_connections!
    conn.establish_connection(db: db)
    yield ActiveRecord::Base.connection.raw_connection
  ensure
    ActiveRecord::Base.connection_handler.clear_active_connections!
    ActiveRecord::Base.connection_handler = original_connection_handler
  end

  context 'with default' do
    it 'has correct all_dbs' do
      expect(conn.all_dbs).to eq(['default'])
    end

    context 'with current' do
      it "has default current db" do
        expect(conn.current_db).to eq('default')
      end

      it "has current hostname" do
        expect(conn.current_hostname).to eq('default.localhost')
      end
    end

    it 'yields self for with_connection' do
      x = conn.with_connection("default") do
        "hi"
      end

      expect(x).to eq("hi")
    end

  end

  it "inherits prepared_statements" do
    load_db_config("database_without_prepared_statements.yml")
    conn.config_filename = fixture_path("two_dbs.yml")
    expect(conn.connection_spec(db: "second").config[:prepared_statements]).to be(false)
    load_db_config("database.yml")
  end

  context 'with two dbs' do
    before do
      conn.config_filename = fixture_path("two_dbs.yml")
    end

    it 'accepts a symbol for the db name' do
      with_connection(:second) do
        expect(conn.current_db).to eq('second')
      end

      expect(conn.current_db).to eq('default')
    end

    it "can exectue a queries concurrently per db" do
      threads = Set.new

      conn.each_connection(threads: 2) do
        sleep 0.002
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
        expect(e.to_s).to include("boom")
      end
    end

    it "has correct all_dbs" do
      expect(conn.all_dbs).to eq(['default', 'second'])
    end

    context 'with second db' do
      it "is configured correctly" do
        with_connection('second') do
          expect(conn.current_db).to eq('second')
          expect(conn.current_hostname).to eq("second.localhost")
        end
      end
    end

    context 'with data partitioning' do
      after do
        ['default', 'second'].each do |db|
          with_connection(db) do |cnn|
            cnn.execute("drop table people") rescue nil
          end
        end
      end

      it 'partitions data correctly' do

        ['default', 'second'].map do |db|

          with_connection(db) do |cnn|
            cnn.execute("create table if not exists people(id INTEGER PRIMARY KEY AUTOINCREMENT, db)")
          end
        end

        SQLite3::Database.query_log.clear

        5.times do
          ['default', 'second'].map do |db|
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
            lists << Person.order(:id).to_a.map { |p| [p.id, p.db] }
          end
        end

        expect(lists[1]).to eq((1..5).map { |id| [id, "second"] })
        expect(lists[0]).to eq((1..5).map { |id| [id, "default"] })

      end
    end

    describe "reloading" do
      context "when config is unchanged" do
        it "maintains the same connection handlers" do
          default_spec = conn.connection_spec(db: "default")
          second_spec = conn.connection_spec(db: "second")

          conn.reload

          expect(default_spec).to eq(conn.connection_spec(db: "default"))
          expect(second_spec).to eq(conn.connection_spec(db: "second"))
        end
      end

      context "when site config is updated" do
        it "updates that connection handler" do
          default_spec = conn.connection_spec(db: "default")
          second_spec = conn.connection_spec(db: "second")

          conn.instance.instance_variable_set(:@config_filename, fixture_path("two_dbs_updated.yml"))
          conn.reload

          expect(default_spec).to eq(conn.connection_spec(db: "default"))
          expect(second_spec).not_to eq(conn.connection_spec(db: "second"))
        end
      end

      context "when sites are added and removed" do
        it "adds and removes connection specs" do
          default_spec = conn.connection_spec(db: "default")
          second_spec = conn.connection_spec(db: "second")

          conn.instance.instance_variable_set(:@config_filename, fixture_path("three_dbs.yml"))
          conn.reload

          expect(default_spec).to eq(conn.connection_spec(db: "default"))
          expect(second_spec).to eq(conn.connection_spec(db: "second"))
          expect(conn.connection_spec(db: "third")).not_to eq(nil)

          conn.instance.instance_variable_set(:@config_filename, fixture_path("two_dbs.yml"))
          conn.reload

          expect(default_spec).to eq(conn.connection_spec(db: "default"))
          expect(second_spec).to eq(conn.connection_spec(db: "second"))
          expect(conn.connection_spec(db: "third")).to eq(nil)
        end
      end
    end
  end

  describe '.current_hostname' do
    before do
      conn.config_filename = fixture_path("two_dbs.yml")
    end

    it 'should return the right hostname' do
      with_connection('default') do
        expect(conn.current_hostname).to eq('default.localhost')
      end

      with_connection('second') do
        expect(conn.current_hostname).to eq('second.localhost')

        conn.config_filename = fixture_path("two_dbs_updated.yml")

        expect(conn.current_hostname).to eq('seconded.localhost')
      end
    end
  end

  describe '.current_db_hostnames' do
    before do
      conn.config_filename = fixture_path("two_dbs.yml")
    end

    it 'should return the right hostname' do
      with_connection('default') do
        expect(conn.current_db_hostnames).to contain_exactly('default.localhost')
      end

      with_connection('second') do
        expect(conn.current_db_hostnames).to contain_exactly('2nd.localhost', 'second.localhost')
      end
    end
  end

  describe '.default_connection_handler=' do
    before do
      conn.config_filename = fixture_path("two_dbs.yml")
    end

    it 'should raise the right error if attempting to assign an invalid argument' do
      expect do
        conn.default_connection_handler = 'test'
      end.to raise_error(ArgumentError)
    end

    it 'should allow the default connection handler to be assigned' do
      default_handler = ActiveRecord::Base.connection_handler
      new_handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new

      conn.default_connection_handler = new_handler
      conn.establish_connection(db: described_class::DEFAULT)

      expect(ActiveRecord::Base.connection_handler).to eq(new_handler)

      conn.default_connection_handler = default_handler
      conn.establish_connection(db: described_class::DEFAULT)

      expect(ActiveRecord::Base.connection_handler).to eq(default_handler)
    end
  end

end
