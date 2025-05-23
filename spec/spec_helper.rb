require 'rspec'
require 'active_record'
require 'factory_bot'
require 'database_cleaner-active_record'
require 'rack/test'
require 'sinatra'

# Set test environment
ENV['RACK_ENV'] = 'test'

require_relative '../config/database'
require_relative '../lib/models'

# Load all lib files for testing
Dir[File.join(__dir__, '..', 'lib', '**', '*.rb')].each { |f| require f }

# Configure Sinatra for testing
class Sinatra::Application
  configure :test do
    enable :sessions
    set :session_secret, 'test_secret'
    set :raise_errors, true
    set :dump_errors, false
    set :show_exceptions, false
  end
end

require_relative '../web_app'

# Test helpers
module TestHelpers
  def app
    Sinatra::Application
  end

  def session
    last_request.env['rack.session']
  end
end

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include TestHelpers
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end

# Set up test environment variables
ENV['VIOLENCE_THRESHOLD'] ||= '0.8'
ENV['TOXICITY_THRESHOLD'] ||= '0.7'

# Load factories
require_relative 'factories'

# Custom RSpec matchers for ActiveRecord models
RSpec::Matchers.define :have_many do |association|
  match do |actual|
    reflection = actual.class.reflect_on_association(association)
    return false unless reflection && reflection.macro == :has_many
    
    if @foreign_key && reflection.foreign_key.to_s != @foreign_key.to_s
      return false
    end
    
    if @primary_key
      actual_primary_key = reflection.options[:primary_key] || actual.class.primary_key
      return false unless actual_primary_key.to_s == @primary_key.to_s
    end
    
    true
  end

  chain :with_foreign_key do |key|
    @foreign_key = key
  end

  chain :with_primary_key do |key|
    @primary_key = key
  end

  failure_message do |actual|
    reflection = actual.class.reflect_on_association(association)
    if reflection.nil?
      "expected #{actual.class} to have many #{association}"
    elsif reflection.macro != :has_many
      "expected #{actual.class} to have many #{association}, but found #{reflection.macro}"
    elsif @foreign_key && reflection.foreign_key.to_s != @foreign_key.to_s
      "expected #{actual.class} to have many #{association} with foreign key #{@foreign_key}, but got #{reflection.foreign_key}"
    elsif @primary_key
      actual_primary_key = reflection.options[:primary_key] || actual.class.primary_key
      "expected #{actual.class} to have many #{association} with primary key #{@primary_key}, but got #{actual_primary_key}"
    end
  end
end

RSpec::Matchers.define :belong_to do |association|
  match do |actual|
    reflection = actual.class.reflect_on_association(association)
    return false unless reflection && reflection.macro == :belongs_to
    
    if @foreign_key && reflection.foreign_key.to_s != @foreign_key.to_s
      return false
    end
    
    if @primary_key
      actual_primary_key = reflection.options[:primary_key] || reflection.klass.primary_key
      return false unless actual_primary_key.to_s == @primary_key.to_s
    end
    
    if @class_name && reflection.options[:class_name] != @class_name
      return false
    end
    
    if @optional_check
      return false unless reflection.options[:optional] == true
    end
    
    true
  end

  chain :with_foreign_key do |key|
    @foreign_key = key
  end

  chain :with_primary_key do |key|
    @primary_key = key
  end

  chain :class_name do |name|
    @class_name = name
  end

  chain :optional do
    @optional_check = true
  end

  failure_message do |actual|
    reflection = actual.class.reflect_on_association(association)
    if reflection.nil?
      "expected #{actual.class} to belong to #{association}"
    elsif reflection.macro != :belongs_to
      "expected #{actual.class} to belong to #{association}, but found #{reflection.macro}"
    elsif @foreign_key && reflection.foreign_key.to_s != @foreign_key.to_s
      "expected #{actual.class} to belong to #{association} with foreign key #{@foreign_key}, but got #{reflection.foreign_key}"
    elsif @primary_key
      actual_primary_key = reflection.options[:primary_key] || reflection.klass.primary_key
      "expected #{actual.class} to belong to #{association} with primary key #{@primary_key}, but got #{actual_primary_key}"
    elsif @class_name && reflection.options[:class_name] != @class_name
      "expected #{actual.class} to belong to #{association} with class name #{@class_name}, but got #{reflection.options[:class_name]}"
    elsif @optional_check && reflection.options[:optional] != true
      "expected #{actual.class} to belong to #{association} to be optional, but it's not"
    end
  end
end

RSpec::Matchers.define :define_enum_for do |enum_name|
  match do |actual|
    if actual.class.respond_to?(:defined_enums)
      enum_definition = actual.class.defined_enums[enum_name.to_s]
      return false unless enum_definition
      
      if @with_values
        return enum_definition == @with_values.stringify_keys
      end
      
      true
    else
      false
    end
  end

  chain :with_values do |values|
    @with_values = values
  end

  failure_message do |actual|
    if !actual.class.respond_to?(:defined_enums)
      "expected #{actual.class} to define enums, but it doesn't respond to defined_enums"
    elsif !actual.class.defined_enums[enum_name.to_s]
      "expected #{actual.class} to define enum #{enum_name}, but it doesn't"
    elsif @with_values
      actual_values = actual.class.defined_enums[enum_name.to_s]
      "expected #{actual.class} to define enum #{enum_name} with values #{@with_values}, but got #{actual_values}"
    end
  end
end
