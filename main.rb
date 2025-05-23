#!/usr/bin/env ruby

require 'telegram/bot'
require 'dotenv/load'
require 'logger'
require 'fileutils'

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

# Configure logging
logger = Logger.new(STDOUT)
logger.level = Logger.const_get(ENV['LOG_LEVEL'] || 'INFO')
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

# Environment variables
TELEGRAM_TOKEN = ENV["BILLY_TELEGRAM_TOKEN"]
BOT_USERNAME = ENV["BILLY_BOT_NAME"]

# Test logging at startup
logger.info("=== Bot Starting ===")
logger.info("- BILLY_TELEGRAM_TOKEN: #{TELEGRAM_TOKEN ? 'SET' : 'NOT SET'}")
logger.info("- ANTHROPIC_API_KEY: #{ENV['ANTHROPIC_API_KEY'] ? 'SET' : 'NOT SET'}")
logger.info("- BILLY_BOT_NAME: #{BOT_USERNAME}")

unless TELEGRAM_TOKEN && BOT_USERNAME
  logger.error("Missing required environment variables")
  exit 1
end

# DEFINE ALL METHODS FIRST
def handle_start_command(bot, message, user)
  welcome_text = <<~TEXT
    👋 Hi #{user.first_name}! I'm an advanced AI bot powered by Claude.

    🤖 Chat Features:
    • Tag me with @#{ENV['BILLY_BOT_NAME']} to chat with Claude
    • I help moderate chats and provide helpful responses

    💰 Points System:
    • Earn points by being active: #{user.points} points
    • Use /daily for daily bonus
    • Use /points to see your stats
    • Use /leaderboard to see top users

    🎯 Commands:
    • /help - See all commands
    • /status - Check your account
    • /points - View your points
    • /daily - Claim daily bonus

    Your current role: #{user.role.capitalize}
    Rank: ##{PointsService.get_user_rank(user)}
  TEXT

  bot.api.send_message(
    chat_id: message.chat.id,
    text: welcome_text,
    reply_to_message_id: message.message_id
  )
end

def handle_help_command(bot, message, user)
  help_text = <<~TEXT
    🤖 Bot Commands

    Basic Commands:
    • Tag @#{ENV['BILLY_BOT_NAME']} + message - Chat with Claude
    • /status - Check your account status
    • /help - Show this help message

    💰 Points Commands:
    • /points [@user] - View points (yours or someone else's)
    • /daily - Claim daily bonus
    • /leaderboard - See top users
    • /transfer @user amount [reason] - Transfer points
    • /give @user amount [reason] - Give points (Mod+)

  TEXT

  if user.moderator? || user.admin?
    help_text += <<~TEXT
      🛡️ Moderator Commands:
      • /ban @user [reason] - Ban a user
      • /unban @user - Unban a user
      • /mute @user [hours] [reason] - Mute a user
      • /warn @user [reason] - Warn a user
      • /stats [@user] - Show user or chat stats
      • /moderation [on|off|settings] - Manage moderation

    TEXT
  end

  if user.admin?
    help_text += <<~TEXT
      👑 Admin Commands:
      • /promote @user [moderator|admin] - Promote user
      • /demote @user - Demote user to regular user
      • /cleanup - Clean up expired bans

      🌐 Web Admin Panel:
      Access the web admin panel at: http://your-server:3000
      Username: admin | Password: (check your .env file)

    TEXT
  end

  bot.api.send_message(
    chat_id: message.chat.id,
    text: help_text,
    reply_to_message_id: message.message_id
  )
end

def handle_status_command(bot, message, user)
  status_emoji = case user.status
                 when 'active' then '✅'
                 when 'warned' then '⚠️'
                 when 'muted' then '🔇'
                 when 'banned' then '🚫'
                 end

  rank = PointsService.get_user_rank(user)
  recent_points = user.point_transactions.where('created_at > ?', 7.days.ago).sum(:amount)

  status_text = <<~TEXT
    📋 Your Status

    👤 Name: #{user.first_name}
    🎖️ Role: #{user.role.capitalize}
    #{status_emoji} Status: #{user.status.capitalize}
    
    💰 Points Summary:
    • Current Points: #{user.points}
    • Rank: ##{rank}
    • Points this week: #{recent_points > 0 ? '+' : ''}#{recent_points}
    • Total earned: #{user.total_points_earned}
    
    📊 Activity:
    • Messages sent: #{user.message_count}
    • Warnings: #{user.warning_count}/3
    • Member since: #{user.created_at.strftime('%Y-%m-%d')}
  TEXT

  if user.banned_until
    status_text += "\n⏰ Restriction until: #{user.banned_until.strftime('%Y-%m-%d %H:%M')}"
  end

  bot.api.send_message(
    chat_id: message.chat.id,
    text: status_text,
    reply_to_message_id: message.message_id
  )
end

def handle_claude_mention(bot, message, user, chat_session, text, claude_service, logger)
  # Extract the query (everything after the bot's username)
  query = text #.split("@#{ENV['BILLY_BOT_NAME']}", 2)[1].to_s.strip
  
  if query.empty?
    bot.api.send_message(
      chat_id: message.chat.id,
      text: "Питай мене шось, йобана",
      reply_to_message_id: message.message_id
    )
    return
  end

  # Show typing indicator
  processing_message = bot.api.send_message(
    chat_id: message.chat.id,
    text: "Піжди єбать...",
    reply_to_message_id: message.message_id
  )

  begin
    # Build context for Claude
    context = {
      user_role: user.role,
      chat_type: chat_session.chat_type,
      user_name: user.first_name || user.username || "User",
      user_points: user.points || 0
    }

    logger.info("Sending to Claude: #{query.length > 100 ? query[0..100] + '...' : query}")

    # Get Claude's response
    claude_response = claude_service.generate_response(query, context)

    if claude_response && !claude_response.empty?
      # Store the interaction
      begin
        Message.create!(
          telegram_message_id: message.message_id,
          telegram_user_id: user.telegram_id,
          telegram_chat_id: chat_session.chat_id,
          content: query,
          claude_response: claude_response,
          message_type: 'claude_query'
        )
      rescue => e
        logger.error("Failed to store message: #{e.message}")
      end

      # Award points for using Claude (limited)
      if rand < 0.3 # 30% chance
        begin
          reward = PointsService.reward_activity(user, :helpful_response, chat_session.chat_id)
          if reward && reward > 0
            claude_response += "\n\n✨ +#{reward} points for engaging with Claude!"
          end
        rescue => e
          logger.error("Failed to award points: #{e.message}")
        end
      end

      # Handle long responses
      if claude_response.length > 4000
        parts = claude_response.scan(/.{1,4000}/)
        parts.each_with_index do |part, index|
          if index == 0
            bot.api.edit_message_text(
              chat_id: message.chat.id,
              message_id: processing_message.message_id,
              text: part
            )
          else
            bot.api.send_message(
              chat_id: message.chat.id,
              text: part,
              reply_to_message_id: message.message_id
            )
          end
          sleep(0.1)
        end
      else
        bot.api.edit_message_text(
          chat_id: message.chat.id,
          message_id: processing_message.message_id,
          text: claude_response
        )
      end
    else
      bot.api.edit_message_text(
        chat_id: message.chat.id,
        message_id: processing_message.message_id,
        text: "🤖 I couldn't generate a response right now. Please try asking differently."
      )
    end

  rescue => e
    logger.error("Claude response error: #{e.class}: #{e.message}")
    logger.error(e.backtrace.first(5).join("\n"))
    
    error_message = case e.class.to_s
                   when /Timeout/, /Net::TimeoutError/
                     "⏱️ Request timed out. Please try again."
                   when /APIError/, /HTTP/
                     "🔌 AI service temporarily unavailable. Try again in a moment."
                   when /JSON/
                     "📝 Response format error. Please try again."
                   else
                     "🤖 Technical error occurred. Please try again or contact admin."
                   end
    
    begin
      bot.api.edit_message_text(
        chat_id: message.chat.id,
        message_id: processing_message.message_id,
        text: error_message
      )
    rescue => edit_error
      logger.error("Failed to edit error message: #{edit_error.message}")
      begin
        bot.api.send_message(
          chat_id: message.chat.id,
          text: error_message,
          reply_to_message_id: message.message_id
        )
      rescue => send_error
        logger.error("Failed to send error message: #{send_error.message}")
      end
    end
  end
end

def handle_pending_deletions(bot, chat_session)
  pending_deletions = chat_session.get_setting('pending_deletions', [])
  return if pending_deletions.empty?

  pending_deletions.each do |message_id|
    begin
      bot.api.delete_message(
        chat_id: chat_session.chat_id,
        message_id: message_id
      )
    rescue
      # Ignore errors (message might already be deleted)
    end
  end

  chat_session.set_setting('pending_deletions', [])
end

def mention_by_nic_name?(text)
   nicknames = [
    'billie', 'billy', 'біллі', 'білі', 'бiллi',
    'наш друган', 'друган', 'бот', 'bot', 'помічник', 'assistant',
    'claude', 'клод'
  ]
  text_lower = text.downcase
  nicknames.any? { |nickname| text_lower.include?(nickname.downcase) }
end

# Initialize services
logger.info("Initializing services...")
begin
  claude_service = ClaudeService.new
  logger.info("✅ Claude service initialized")
rescue => e
  logger.error("❌ Failed to initialize Claude service: #{e.message}")
end

moderation_service = ModerationService.new(claude_service)
rate_limiter = RateLimiter.new

logger.info("Bot starting with Claude 4 Sonnet and Web Admin UI...")

# Start the bot
Telegram::Bot::Client.run(TELEGRAM_TOKEN) do |bot|
  admin_handler = AdminHandler.new(bot)
  points_handler = PointsHandler.new(bot)
  logger.info('✅ Bot started successfully')

  bot.listen do |message|
    begin
      case message
      when Telegram::Bot::Types::Message
        next unless message.text || message.caption

        # Skip old messages (older than 24 hours)
        message_time = Time.at(message.date)
        if Time.current - message_time > 24.hours
          logger.debug("Skipping old message from #{message.from.id}: #{(Time.current - message_time).to_i} seconds old")
          next
        end

        # Get or create user and chat
        user = UserService.find_or_create_user(message.from)
        chat_session = UserService.find_or_create_chat(message.chat)

        # # Rate limiting
        # unless rate_limiter.check_rate_limit(user.telegram_id, chat_session.chat_id)
        #   bot.api.send_message(
        #     chat_id: message.chat.id,
        #     text: "🐌 Rate limit exceeded. Try again later.",
        #     reply_to_message_id: message.message_id
        #   )
        #   next
        # end

        # Update user activity and award points for participation
        user.update!(
          message_count: user.message_count + 1,
          last_interaction: Time.current
        )

        # Award activity points (limited to prevent spam)
        if rand < 0.1 # 10% chance to get points for regular messages
          PointsService.reward_activity(user, :message_sent, chat_session.chat_id)
        end

        # Handle commands
        text = message.text || message.caption || ''
        
        if text.start_with?('/')
          command_parts = text.split
          command = command_parts[0]
          args = command_parts[1..]

          case command
          when '/start'
            handle_start_command(bot, message, user)
            next
          when '/help'
            handle_help_command(bot, message, user)
            next
          when '/status'
            handle_status_command(bot, message, user)
            next
          
          # Points commands
          when '/points', '/give', '/leaderboard', '/top', '/daily', '/transfer'
            if points_handler.handle_points_command(message, user, chat_session, command, args)
              next
            end
          
          # Admin commands
          when '/ban', '/unban', '/mute', '/warn', '/promote', '/demote', '/stats', '/moderation', '/cleanup'
            if admin_handler.handle_admin_command(message, user, chat_session, command, args)
              next
            else
              bot.api.send_message(
                chat_id: message.chat.id,
                text: "Куда поліз?",
                reply_to_message_id: message.message_id
              )
              next
            end
          end
        end

        # Process message for moderation
        stored_message = moderation_service.process_message(message, user, chat_session)

        # Handle Claude mentions
        if text.include?("@#{BOT_USERNAME}") || mention_by_nic_name?(text)
          # Check if user can send messages
          unless UserService.can_user_message?(user, chat_session)
            if user.banned?
              bot.api.send_message(
                chat_id: message.chat.id,
                text: "Пішов нахуй",
                reply_to_message_id: message.message_id
              )
            elsif user.muted?
              remaining_time = user.banned_until ? 
                ((user.banned_until - Time.current) / 60).round : 0
              bot.api.send_message(
                chat_id: message.chat.id,
                text: "Я з тобою не піжжу ше #{remaining_time} хвилин",
                reply_to_message_id: message.message_id
              )
            end
            next
          end
          logger.info("Claude mention detected from user #{user.telegram_id}")
          handle_claude_mention(bot, message, user, chat_session, text, claude_service, logger)
        end

        # Handle pending message deletions
        handle_pending_deletions(bot, chat_session)
      end
    rescue => e
      logger.error("❌ Error processing message: #{e.class}: #{e.message}")
      logger.error("Backtrace: #{e.backtrace.first(10).join("\n")}")
      
      begin
        error_response = case e.class.to_s
                        when /API/, /HTTP/
                          "🔌 Service temporarily unavailable. Please try again."
                        when /Timeout/
                          "⏱️ Request timed out. Please try again."
                        when /JSON/
                          "📝 Data processing error. Please try again."
                        else
                          "🤖 Temporary error. Please try again or contact admin."
                        end
        
        bot.api.send_message(
          chat_id: message.chat.id,
          text: error_response,
          reply_to_message_id: message.message_id
        )
      rescue => send_error
        logger.error("Failed to send error message: #{send_error.message}")
      end
    end
  end
end

# Background tasks
Thread.new do
  loop do
    begin
      # Clean up expired sessions and bans
      UserService.cleanup_expired_bans
      AdminSession.cleanup_expired
      
      # Award daily bonuses for very active users
      User.joins(:messages)
         .where('messages.created_at > ?', 1.hour.ago)
         .group('users.telegram_id')
         .having('COUNT(messages.id) >= 10')
         .each do |user|
           PointsService.reward_activity(user, :daily_activity)
         end
      
      sleep 3600 # Run every hour
    rescue => e
      logger.error("Background task error: #{e.message}")
    end
  end
end
