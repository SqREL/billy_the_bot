#!/usr/bin/env ruby

require 'dotenv/load'

# Load our application
require_relative 'config/database'
require_relative 'lib/models'
require_relative 'lib/services/claude_service'
require_relative 'lib/services/moderation_service'
require_relative 'lib/services/user_service'
require_relative 'lib/services/points_service'
require_relative 'lib/middleware/rate_limiter'
require_relative 'lib/handlers/admin_handler'
require_relative 'lib/handlers/points_handler'
require_relative 'lib/bot_manager'
require_relative 'lib/message_handler'
require_relative 'lib/command_handlers'
require_relative 'lib/claude_interaction_handler'
require_relative 'lib/background_tasks'

# Start the bot
begin
  bot_manager = BotManager.new
  BackgroundTasks.start(bot_manager.logger)
  bot_manager.start
rescue Interrupt
  puts "\n👋 Bot shutting down gracefully..."
rescue => e
  puts "❌ Fatal error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end