class ModerationService
  VIOLENT_KEYWORDS = [
    'kill', 'murder', 'die', 'death', 'violence', 'fight', 'attack', 
    'hurt', 'harm', 'destroy', 'eliminate', 'terminate'
  ].freeze

  TOXIC_KEYWORDS = [
    'hate', 'stupid', 'idiot', 'moron', 'loser', 'worthless',
    'disgusting', 'pathetic', 'garbage', 'trash'
  ].freeze

  def initialize(claude_service = ClaudeService.new)
    @claude = claude_service
  end

  def process_message(telegram_message, user, chat_session)
    return unless chat_session.moderation_enabled?
    return unless ENV['ENABLE_AUTO_MODERATION'] == 'true'

    content = telegram_message.text || telegram_message.caption || ''
    return if content.empty?

    # Quick keyword check first
    keyword_analysis = analyze_keywords(content)
    
    # Deep analysis with Claude if needed
    claude_analysis = @claude.analyze_content(content)

    # Store message with analysis
    message = Message.create!(
      telegram_message_id: telegram_message.message_id,
      telegram_user_id: user.telegram_id,
      telegram_chat_id: chat_session.chat_id,
      content: content,
      message_type: determine_message_type(telegram_message),
      violence_score: [keyword_analysis[:violence_score], claude_analysis[:violence_score]].max,
      toxicity_score: [keyword_analysis[:toxicity_score], claude_analysis[:toxicity_score]].max,
      metadata: {
        keyword_flags: keyword_analysis[:flags],
        claude_safe: claude_analysis[:safe]
      }
    )

    # Take action if needed
    take_moderation_action(message, user, chat_session, telegram_message)

    message
  end

  def take_moderation_action(message, user, chat_session, telegram_message)
    action_taken = false

    if message.violent? || message.toxic?
      message.update!(flagged: true, flag_reason: determine_flag_reason(message))
      
      # Escalate based on severity and user history
      if should_auto_moderate?(message, user)
        case determine_action_severity(message, user)
        when :warn
          warn_user(user, chat_session, message, "Inappropriate content detected")
          action_taken = true
        when :mute
          mute_user(user, chat_session, message, "Toxic behavior")
          action_taken = true
        when :ban
          ban_user(user, chat_session, message, "Severe violation")
          action_taken = true
        end
      end
    end

    # Delete message if flagged and auto-delete is enabled
    if message.flagged? && chat_session.get_setting('auto_delete_flagged', false)
      delete_message(telegram_message, chat_session)
    end

    action_taken
  end

  def warn_user(user, chat_session, message, reason)
    user.increment_warnings!
    
    ModerationLog.create!(
      user_id: user.telegram_id,
      chat_id: chat_session.chat_id,
      message_id: message.id,
      action: :warned,
      reason: reason,
      details: { warning_count: user.warning_count }
    )
  end

  def mute_user(user, chat_session, message, reason)
    user.update!(status: :muted, banned_until: 1.hour.from_now)
    
    ModerationLog.create!(
      user_id: user.telegram_id,
      chat_id: chat_session.chat_id,
      message_id: message.id,
      action: :muted,
      reason: reason,
      details: { duration: '1 hour' }
    )
  end

  def ban_user(user, chat_session, message, reason)
    duration = determine_ban_duration(user)
    user.update!(status: :banned, banned_until: duration)
    
    ModerationLog.create!(
      user_id: user.telegram_id,
      chat_id: chat_session.chat_id,
      message_id: message.id,
      action: :banned,
      reason: reason,
      details: { duration: duration&.iso8601 }
    )
  end

  private

  def analyze_keywords(content)
    content_lower = content.downcase
    flags = []
    violence_score = 0.0
    toxicity_score = 0.0

    VIOLENT_KEYWORDS.each do |keyword|
      if content_lower.include?(keyword)
        flags << "violent_keyword: #{keyword}"
        violence_score += 0.2
      end
    end

    TOXIC_KEYWORDS.each do |keyword|
      if content_lower.include?(keyword)
        flags << "toxic_keyword: #{keyword}"
        toxicity_score += 0.15
      end
    end

    {
      violence_score: [violence_score, 1.0].min,
      toxicity_score: [toxicity_score, 1.0].min,
      flags: flags
    }
  end

  def determine_message_type(telegram_message)
    return 'photo' if telegram_message.photo&.any?
    return 'document' if telegram_message.document
    return 'video' if telegram_message.video
    return 'audio' if telegram_message.audio
    return 'voice' if telegram_message.voice
    return 'sticker' if telegram_message.sticker
    'text'
  end

  def determine_flag_reason(message)
    reasons = []
    reasons << "High violence score (#{message.violence_score.round(2)})" if message.violent?
    reasons << "High toxicity score (#{message.toxicity_score.round(2)})" if message.toxic?
    reasons.join(', ')
  end

  def should_auto_moderate?(message, user)
    # Don't auto-moderate admins or moderators
    return false if user.admin? || user.moderator?
    
    # Auto-moderate if score is very high
    return true if message.violence_score > 0.9 || message.toxicity_score > 0.9
    
    # Consider user history
    recent_violations = user.messages.recent.flagged.count
    return true if recent_violations >= 2 && (message.violent? || message.toxic?)
    
    false
  end

  def determine_action_severity(message, user)
    # Severe violations get immediate ban
    return :ban if message.violence_score > 0.9
    
    # High toxicity with repeat offense
    return :ban if message.toxicity_score > 0.8 && user.warning_count >= 2
    
    # Moderate violations get mute
    return :mute if message.violence_score > 0.7 || message.toxicity_score > 0.7
    
    # Lower violations get warning
    :warn
  end

  def determine_ban_duration(user)
    case user.warning_count
    when 0..1
      1.hour.from_now
    when 2
      24.hours.from_now
    when 3
      7.days.from_now
    else
      nil # permanent
    end
  end

  def delete_message(telegram_message, chat_session)
    # This would need to be called from the bot context
    # Storing for later deletion by the bot
    chat_session.set_setting('pending_deletions', 
      (chat_session.get_setting('pending_deletions', []) + [telegram_message.message_id]))
  end
end
