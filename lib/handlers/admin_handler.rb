class AdminHandler
  def initialize(bot, user_service = UserService)
    @bot = bot
    @user_service = user_service
  end

  def handle_admin_command(message, user, chat_session, command, args)
    return false unless user.admin? || user.moderator?

    command_handlers = {
      '/ban' => -> { handle_ban_command(message, user, args) },
      '/unban' => -> { handle_unban_command(message, user, args) },
      '/mute' => -> { handle_mute_command(message, user, args) },
      '/warn' => -> { handle_warn_command(message, user, args) },
      '/promote' => -> { handle_promote_command(message, user, args) },
      '/demote' => -> { handle_demote_command(message, user, args) },
      '/stats' => -> { handle_stats_command(message, user, chat_session, args) },
      '/moderation' => -> { handle_moderation_command(message, user, chat_session, args) },
      '/cleanup' => -> { handle_cleanup_command(message, user) }
    }

    handler = command_handlers[command]
    handler ? handler.call : false
  end

  private

  def handle_ban_command(message, admin, args)
    if args.empty?
      send_error(message, "Usage: /ban @username [reason]")
      return true
    end

    username = extract_username(args[0])
    reason = args[1..].join(' ') || "No reason provided"

    target_user = User.find_by(username: username)
    unless target_user
      send_error(message, "User not found")
      return true
    end

    if target_user.admin?
      send_error(message, "Cannot ban admins")
      return true
    end

    target_user.update!(status: :banned, banned_until: nil)
    
    ModerationLog.create!(
      user_id: target_user.telegram_id,
      chat_id: message.chat.id,
      action: :banned,
      reason: reason,
      moderator_id: admin.telegram_id,
      details: { permanent: true }
    )

    send_response(message, "✅ User @#{username} has been permanently banned.\nReason: #{reason}")
    true
  end

  def handle_unban_command(message, admin, args)
    return send_error(message, "Usage: /unban @username") if args.empty?

    username = extract_username(args[0])
    target_user = User.find_by(username: username)
    return send_error(message, "User not found") unless target_user

    target_user.update!(status: :active, banned_until: nil, warning_count: 0)
    
    ModerationLog.create!(
      user_id: target_user.telegram_id,
      chat_id: message.chat.id,
      action: :unbanned,
      reason: "Unbanned by admin",
      moderator_id: admin.telegram_id
    )

    send_response(message, "✅ User @#{username} has been unbanned and warnings cleared.")
    true
  end

  def handle_mute_command(message, admin, args)
    if args.empty?
      send_error(message, "Usage: /mute @username [duration_hours] [reason]")
      return true
    end

    username = extract_username(args[0])
    duration_hours = args[1]&.to_i || 1
    reason = (args[2..] || []).join(' ')
    reason = "No reason provided" if reason.empty?

    target_user = User.find_by(username: username)
    unless target_user
      send_error(message, "User not found")
      return true
    end
    
    if target_user.admin?
      send_error(message, "Cannot mute admins")
      return true
    end

    target_user.update!(
      status: :muted, 
      banned_until: duration_hours.hours.from_now
    )
    
    ModerationLog.create!(
      user_id: target_user.telegram_id,
      chat_id: message.chat.id,
      action: :muted,
      reason: reason,
      moderator_id: admin.telegram_id,
      details: { duration_hours: duration_hours }
    )

    send_response(message, "✅ User @#{username} muted for #{duration_hours} hours.\nReason: #{reason}")
    true
  end

  def handle_warn_command(message, admin, args)
    return send_error(message, "Usage: /warn @username [reason]") if args.empty?

    username = extract_username(args[0])
    reason = args[1..].join(' ') || "No reason provided"

    target_user = User.find_by(username: username)
    return send_error(message, "User not found") unless target_user
    return send_error(message, "Cannot warn admins") if target_user.admin?

    target_user.increment_warnings!
    
    ModerationLog.create!(
      user_id: target_user.telegram_id,
      chat_id: message.chat.id,
      action: :warned,
      reason: reason,
      moderator_id: admin.telegram_id,
      details: { warning_count: target_user.warning_count }
    )

    send_response(message, "⚠️ User @#{username} warned (#{target_user.warning_count}/3).\nReason: #{reason}")
    true
  end

  def handle_promote_command(message, admin, args)
    return nil unless admin.admin? # Only admins can promote
    
    if args.empty?
      send_error(message, "Usage: /promote @username [moderator|admin]")
      return true
    end

    username = extract_username(args[0])
    role = args[1] || 'moderator'
    
    unless %w[moderator admin].include?(role)
      send_error(message, "Invalid role")
      return true
    end

    target_user = User.find_by(username: username)
    unless target_user
      send_error(message, "User not found")
      return true
    end

    result = @user_service.promote_user(target_user.telegram_id, role, admin.telegram_id)
    
    if result[:success]
      send_response(message, "✅ #{result[:message]}")
    else
      send_error(message, result[:message])
    end
    true
  end

  def handle_demote_command(message, admin, args)
    return unless admin.admin?
    return send_error(message, "Usage: /demote @username") if args.empty?

    username = extract_username(args[0])
    target_user = User.find_by(username: username)
    return send_error(message, "User not found") unless target_user

    result = @user_service.promote_user(target_user.telegram_id, 'user', admin.telegram_id)
    
    if result[:success]
      send_response(message, "✅ User @#{username} demoted to regular user")
    else
      send_error(message, result[:message])
    end
    true
  end

  def handle_stats_command(message, admin, chat_session, args)
    if args.empty?
      # Chat stats
      stats = @user_service.get_chat_stats(chat_session.chat_id)
      response = format_chat_stats(stats)
    else
      # User stats
      username = extract_username(args[0])
      target_user = User.find_by(username: username)
      return send_error(message, "User not found") unless target_user

      stats = @user_service.get_user_stats(target_user.telegram_id)
      response = format_user_stats(stats)
    end

    send_response(message, response)
    true
  end

  def handle_moderation_command(message, admin, chat_session, args)
    return send_error(message, "Usage: /moderation [on|off|settings]") if args.empty?

    case args[0].downcase
    when 'on'
      chat_session.update!(moderation_enabled: true)
      send_response(message, "✅ Moderation enabled for this chat")
    when 'off'
      chat_session.update!(moderation_enabled: false)
      send_response(message, "❌ Moderation disabled for this chat")
    when 'settings'
      settings = format_moderation_settings(chat_session)
      send_response(message, settings)
    else
      send_error(message, "Invalid option. Use: on, off, or settings")
    end
    true
  end

  def handle_cleanup_command(message, admin)
    return unless admin.admin?

    cleaned = @user_service.cleanup_expired_bans
    send_response(message, "🧹 Cleaned up #{cleaned} expired bans")
    true
  end

  def extract_username(text)
    text.start_with?('@') ? text[1..] : text
  end

  def send_response(message, text)
    @bot.api.send_message(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id)
  end

  def send_error(message, text)
    @bot.api.send_message(chat_id: message.chat.id, text: "❌ #{text}", reply_to_message_id: message.message_id)
  end

  def format_chat_stats(stats)
    return "No stats available" unless stats

    <<~STATS
      📊 Chat Statistics

      💬 Chat: #{stats[:chat_title] || 'Private Chat'}
      📝 Type: #{stats[:chat_type]}
      🛡️ Moderation: #{stats[:moderation_enabled] ? 'Enabled' : 'Disabled'}
      
      📈 Activity:
      • Total messages: #{stats[:total_messages]}
      • Flagged messages: #{stats[:flagged_messages]}
      • Active users (24h): #{stats[:active_users]}
    STATS
  end

  def format_user_stats(stats)
    return "No stats available" unless stats

    status_emoji = case stats[:status]
                   when 'active' then '✅'
                   when 'warned' then '⚠️'
                   when 'muted' then '🔇'
                   when 'banned' then '🚫'
                   end

    <<~STATS
      👤 User Statistics

      🏷️ Name: #{stats[:username]}
      🎖️ Role: #{stats[:role].capitalize}
      #{status_emoji} Status: #{stats[:status].capitalize}
      
      📊 Activity:
      • Total messages: #{stats[:message_count]}
      • Recent messages (24h): #{stats[:recent_messages]}
      • Flagged messages: #{stats[:flagged_messages]}
      • Warnings: #{stats[:warning_count]}/3
      
      📅 Member since: #{stats[:member_since].strftime('%Y-%m-%d')}
      🕐 Last seen: #{stats[:last_interaction].strftime('%Y-%m-%d %H:%M')}
    STATS
  end

  def format_moderation_settings(chat_session)
    settings = chat_session.settings || {}
    
    <<~SETTINGS
      🛡️ Moderation Settings

      Status: #{chat_session.moderation_enabled? ? 'Enabled ✅' : 'Disabled ❌'}
      
      Settings:
      • Auto-delete flagged: #{settings['auto_delete_flagged'] ? 'Yes' : 'No'}
      • Violence threshold: #{ENV['VIOLENCE_THRESHOLD'] || '0.7'}
      • Toxicity threshold: #{ENV['TOXICITY_THRESHOLD'] || '0.8'}
      • Rate limit (per minute): #{ENV['MAX_MESSAGES_PER_MINUTE'] || '10'}
    SETTINGS
  end
end
