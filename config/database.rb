require 'active_record'
require 'sqlite3'
require 'fileutils'

database_url = ENV['DATABASE_URL'] || 'sqlite3://db/bot.sqlite3'

begin
  ActiveRecord::Base.establish_connection(database_url)
  
  # Test the connection
  ActiveRecord::Base.connection.execute("SELECT 1")
  puts "✅ Database connection established"
rescue => e
  puts "❌ Database connection failed: #{e.message}"
  puts "Creating database..."
end

# Create database directory if it doesn't exist
FileUtils.mkdir_p('db') unless Dir.exist?('db')

# Auto-create tables if they don't exist
begin
  ActiveRecord::Schema.define(version: 1) do
    unless ActiveRecord::Base.connection.table_exists?(:users)
      create_table :users do |t|
        t.bigint :telegram_id, null: false
        t.string :username
        t.string :first_name
        t.string :last_name
        t.string :language_code, default: 'en'
        t.integer :role, default: 0
        t.integer :status, default: 0
        t.integer :message_count, default: 0
        t.integer :warning_count, default: 0
        t.integer :points, default: 0
        t.integer :total_points_earned, default: 0
        t.integer :total_points_spent, default: 0
        t.datetime :last_interaction
        t.datetime :banned_until
        t.timestamps
      end
      add_index :users, :telegram_id, unique: true
      puts "✅ Created users table"
    end

    unless ActiveRecord::Base.connection.table_exists?(:chat_sessions)
      create_table :chat_sessions do |t|
        t.bigint :chat_id, null: false
        t.string :chat_type
        t.string :chat_title
        t.integer :member_count
        t.boolean :moderation_enabled, default: true
        t.json :settings
        t.timestamps
      end
      add_index :chat_sessions, :chat_id, unique: true
      puts "✅ Created chat_sessions table"
    end

    unless ActiveRecord::Base.connection.table_exists?(:messages)
      create_table :messages do |t|
        t.bigint :telegram_message_id, null: false
        t.bigint :telegram_user_id, null: false
        t.bigint :telegram_chat_id, null: false
        t.text :content
        t.string :message_type, default: 'text'
        t.text :claude_response
        t.float :violence_score
        t.float :toxicity_score
        t.boolean :flagged, default: false
        t.string :flag_reason
        t.json :metadata
        t.timestamps
      end
      add_index :messages, [:telegram_chat_id, :created_at]
      add_index :messages, [:telegram_user_id, :created_at]
      add_index :messages, :flagged
      puts "✅ Created messages table"
    end

    unless ActiveRecord::Base.connection.table_exists?(:moderation_logs)
      create_table :moderation_logs do |t|
        t.bigint :user_id, null: false
        t.bigint :chat_id, null: false
        t.bigint :message_id
        t.string :action
        t.string :reason
        t.bigint :moderator_id
        t.json :details
        t.timestamps
      end
      add_index :moderation_logs, [:user_id, :created_at]
      puts "✅ Created moderation_logs table"
    end

    unless ActiveRecord::Base.connection.table_exists?(:point_transactions)
      create_table :point_transactions do |t|
        t.bigint :user_id, null: false
        t.bigint :chat_id, null: false
        t.integer :amount, null: false
        t.string :transaction_type
        t.string :reason
        t.bigint :admin_id
        t.json :metadata
        t.timestamps
      end
      add_index :point_transactions, [:user_id, :created_at]
      add_index :point_transactions, [:chat_id, :created_at]
      puts "✅ Created point_transactions table"
    end

    unless ActiveRecord::Base.connection.table_exists?(:message_templates)
      create_table :message_templates do |t|
        t.string :name, null: false
        t.string :template_type
        t.text :content
        t.json :options
        t.string :description
        t.boolean :active, default: true
        t.bigint :created_by
        t.timestamps
      end
      add_index :message_templates, :template_type
      puts "✅ Created message_templates table"
    end

    unless ActiveRecord::Base.connection.table_exists?(:admin_sessions)
      create_table :admin_sessions do |t|
        t.string :session_id, null: false
        t.string :username
        t.string :ip_address
        t.datetime :expires_at
        t.timestamps
      end
      add_index :admin_sessions, :session_id, unique: true
      puts "✅ Created admin_sessions table"
    end

    # Add missing columns to existing users table if needed
    connection = ActiveRecord::Base.connection
    
    unless connection.column_exists?(:users, :points)
      connection.add_column :users, :points, :integer, default: 0
      puts "✅ Added points column to users"
    end
    
    unless connection.column_exists?(:users, :total_points_earned)
      connection.add_column :users, :total_points_earned, :integer, default: 0
      puts "✅ Added total_points_earned column to users"
    end
    
    unless connection.column_exists?(:users, :total_points_spent)
      connection.add_column :users, :total_points_spent, :integer, default: 0
      puts "✅ Added total_points_spent column to users"
    end
    
    # Update existing users to have default points values
    connection.execute("UPDATE users SET points = 0 WHERE points IS NULL")
    connection.execute("UPDATE users SET total_points_earned = 0 WHERE total_points_earned IS NULL")
    connection.execute("UPDATE users SET total_points_spent = 0 WHERE total_points_spent IS NULL")
  end

  puts "✅ Database tables created/updated successfully"
rescue => e
  puts "❌ Database setup failed: #{e.message}"
  puts e.backtrace.join("\n")
end
