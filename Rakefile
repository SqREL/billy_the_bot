require 'rspec/core/rake_task'
require 'active_record'
require_relative 'config/database'

# RSpec tasks
RSpec::Core::RakeTask.new(:spec)

# Database tasks
namespace :db do
  desc "Run database migrations"
  task :migrate do
    ActiveRecord::MigrationContext.new('db/').migrate
  end

  desc "Create test database"
  task :create_test do
    # Set test environment
    ENV['RACK_ENV'] = 'test'
    
    # Create test database if it doesn't exist
    test_db_path = 'db/test.sqlite3'
    unless File.exist?(test_db_path)
      ActiveRecord::Base.establish_connection(
        adapter: 'sqlite3',
        database: test_db_path
      )
      
      # Run migrations
      ActiveRecord::MigrationContext.new('db/').migrate
    end
  end

  desc "Reset test database"
  task :reset_test do
    ENV['RACK_ENV'] = 'test'
    test_db_path = 'db/test.sqlite3'
    
    File.delete(test_db_path) if File.exist?(test_db_path)
    
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: test_db_path
    )
    
    ActiveRecord::MigrationContext.new('db/').migrate
  end
end

# Test task with database setup
desc "Run tests with database setup"
task :test => ['db:create_test', :spec]

# Default task
task :default => :test