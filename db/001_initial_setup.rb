require 'active_record'

class InitialSetup < ActiveRecord::Migration[7.0]
  def up
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
      t.datetime :last_interaction
      t.datetime :banned_until
      t.timestamps
    end

    create_table :chat_sessions do |t|
      t.bigint :chat_id, null: false
      t.string :chat_type
      t.string :chat_title
      t.integer :member_count
      t.boolean :moderation_enabled, default: true
      t.json :settings
      t.timestamps
    end

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

    add_index :users, :telegram_id, unique: true
    add_index :chat_sessions, :chat_id, unique: true
    add_index :messages, [:telegram_chat_id, :created_at]
    add_index :messages, [:telegram_user_id, :created_at]
    add_index :messages, :flagged
    add_index :moderation_logs, [:user_id, :created_at]
  end

  def down
    drop_table :moderation_logs
    drop_table :messages
    drop_table :chat_sessions
    drop_table :users
  end
end
