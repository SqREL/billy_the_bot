require 'active_record'

class AddPointsSystem < ActiveRecord::Migration[7.0]
  def up
    # Add points to users table
    add_column :users, :points, :integer, default: 0
    add_column :users, :total_points_earned, :integer, default: 0
    add_column :users, :total_points_spent, :integer, default: 0

    # Create points transactions table
    create_table :point_transactions do |t|
      t.bigint :user_id, null: false
      t.bigint :chat_id, null: false
      t.integer :amount, null: false
      t.string :transaction_type # earned, spent, admin_given, admin_taken
      t.string :reason
      t.bigint :admin_id
      t.json :metadata
      t.timestamps
    end

    # Create message templates table
    create_table :message_templates do |t|
      t.string :name, null: false
      t.string :template_type # text, poll, quiz, photo
      t.text :content
      t.json :options # for polls/quizzes
      t.string :description
      t.boolean :active, default: true
      t.bigint :created_by
      t.timestamps
    end

    # Create admin sessions table
    create_table :admin_sessions do |t|
      t.string :session_id, null: false
      t.string :username
      t.string :ip_address
      t.datetime :expires_at
      t.timestamps
    end

    add_index :point_transactions, [:user_id, :created_at]
    add_index :point_transactions, [:chat_id, :created_at]
    add_index :message_templates, :template_type
    add_index :admin_sessions, :session_id, unique: true
  end

  def down
    drop_table :admin_sessions
    drop_table :message_templates
    drop_table :point_transactions
    remove_column :users, :points
    remove_column :users, :total_points_earned
    remove_column :users, :total_points_spent
  end
end
