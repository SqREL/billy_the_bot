class MessageHandler
  def initialize(bot, services, logger)
    @bot = bot
    @services = services
    @logger = logger
    @bot_username = ENV["BILLY_BOT_NAME"]
    
    # Initialize handlers that need bot instance
    @services[:admin_handler] = AdminHandler.new(bot)
    @services[:points_handler] = PointsHandler.new(bot)
  end

  def handle_message(message)
    return unless message.is_a?(Telegram::Bot::Types::Message)
    return unless message.text || message.caption

    if old_message?(message)
      @logger.debug("Skipping old message from #{message.from.id}")
      return
    end

    begin
      process_message(message)
    rescue => e
      handle_error(e, message)
    end
  end

  private

  def old_message?(message)
    message_time = Time.at(message.date)
    Time.current - message_time > 24.hours
  end

  def process_message(message)
    user = UserService.find_or_create_user(message.from)
    chat_session = UserService.find_or_create_chat(message.chat)

    update_user_activity(user)
    award_activity_points(user, chat_session)

    text = message.text || message.caption || ''

    if command_message?(text)
      handle_command(message, user, chat_session, text)
    else
      handle_regular_message(message, user, chat_session, text)
    end
  end

  def command_message?(text)
    text.start_with?('/')
  end

  def handle_command(message, user, chat_session, text)
    command_parts = text.split
    command = command_parts[0]
    args = command_parts[1..]

    case command
    when '/start'
      CommandHandlers.handle_start(message, user, @bot)
    when '/help'
      CommandHandlers.handle_help(message, user, @bot)
    when '/status'
      CommandHandlers.handle_status(message, user, @bot)
    when '/points', '/give', '/leaderboard', '/top', '/daily', '/transfer'
      @services[:points_handler].handle_points_command(message, user, chat_session, command, args)
    when '/ban', '/unban', '/mute', '/warn', '/promote', '/demote', '/stats', '/moderation', '/cleanup'
      unless @services[:admin_handler].handle_admin_command(message, user, chat_session, command, args)
        send_unauthorized_message(message)
      end
    end
  end

  def handle_regular_message(message, user, chat_session, text)
    @services[:moderation].process_message(message, user, chat_session)

    if claude_mentioned?(text)
      handle_claude_interaction(message, user, chat_session, text)
    end

    handle_pending_deletions(chat_session)
  end

  def claude_mentioned?(text)
    text.include?("@#{@bot_username}") || mention_by_nickname?(text)
  end

  def mention_by_nickname?(text)
    nicknames = [
      'billie', 'billy', 'біллі', 'білі', 'бiллi',
      'наш друган', 'друган', 'бот', 'bot', 'помічник', 'assistant',
      'claude', 'клод'
    ]
    text_lower = text.downcase
    nicknames.any? { |nickname| text_lower.include?(nickname.downcase) }
  end

  def handle_claude_interaction(message, user, chat_session, text)
    unless UserService.can_user_message?(user, chat_session)
      send_restriction_message(message, user)
      return
    end

    @logger.info("Claude mention detected from user #{user.telegram_id}")
    ClaudeInteractionHandler.handle(message, user, chat_session, text, @services[:claude], @bot, @logger)
  end

  def update_user_activity(user)
    user.update!(
      message_count: user.message_count + 1,
      last_interaction: Time.current
    )
  end

  def award_activity_points(user, chat_session)
    return unless rand < 0.1 # 10% chance
    PointsService.reward_activity(user, :message_sent, chat_session.chat_id)
  end

  def send_unauthorized_message(message)
    @bot.api.send_message(
      chat_id: message.chat.id,
      text: "Куда поліз?",
      reply_to_message_id: message.message_id
    )
  end

  def send_restriction_message(message, user)
    if user.banned?
      @bot.api.send_message(
        chat_id: message.chat.id,
        text: "Пішов нахуй",
        reply_to_message_id: message.message_id
      )
    elsif user.muted?
      remaining_time = user.banned_until ? 
        ((user.banned_until - Time.current) / 60).round : 0
      @bot.api.send_message(
        chat_id: message.chat.id,
        text: "Я з тобою не піжжу ше #{remaining_time} хвилин",
        reply_to_message_id: message.message_id
      )
    end
  end

  def handle_pending_deletions(chat_session)
    pending_deletions = chat_session.get_setting('pending_deletions', [])
    return if pending_deletions.empty?

    pending_deletions.each do |message_id|
      begin
        @bot.api.delete_message(
          chat_id: chat_session.chat_id,
          message_id: message_id
        )
      rescue
        # Ignore errors (message might already be deleted)
      end
    end

    chat_session.set_setting('pending_deletions', [])
  end

  def handle_error(error, message)
    @logger.error("❌ Error processing message: #{error.class}: #{error.message}")
    @logger.error("Backtrace: #{error.backtrace.first(10).join("\n")}")
    
    begin
      error_response = case error.class.to_s
                      when /API/, /HTTP/
                        "🔌 Service temporarily unavailable. Please try again."
                      when /Timeout/
                        "⏱️ Request timed out. Please try again."
                      when /JSON/
                        "📝 Data processing error. Please try again."
                      else
                        "🤖 Temporary error. Please try again or contact admin."
                      end
      
      @bot.api.send_message(
        chat_id: message.chat.id,
        text: error_response,
        reply_to_message_id: message.message_id
      )
    rescue => send_error
      @logger.error("Failed to send error message: #{send_error.message}")
    end
  end
end