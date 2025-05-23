class UserService
  def self.find_or_create_user(telegram_user)
    user = User.find_by(telegram_id: telegram_user.id)
    
    if user
      # Update user info if changed
      user.update!(
        username: telegram_user.username,
        first_name: telegram_user.first_name,
        last_name: telegram_user.last_name,
        language_code: telegram_user.language_code,
        last_interaction: Time.current
      )
    else
      user = User.create!(
        telegram_id: telegram_user.id,
        username: telegram_user.username,
        first_name: telegram_user.first_name,
        last_name: telegram_user.last_name,
        language_code: telegram_user.language_code || 'en',
        last_interaction: Time.current
      )
    end

    user
  end

  def self.find_or_create_chat(telegram_chat)
    chat = ChatSession.find_by(chat_id: telegram_chat.id)
    
    if chat
      # Update chat info
      chat.update!(
        chat_type: telegram_chat.type,
        chat_title: telegram_chat.title
      )
    else
      chat = ChatSession.create!(
        chat_id: telegram_chat.id,
        chat_type: telegram_chat.type,
        chat_title: telegram_chat.title,
        moderation_enabled: telegram_chat.type != 'private'
      )
    end

    chat
  end

  def self.can_user_message?(user, chat_session)
    # Check if user is banned
    return false if user.banned?
    
    # Check if user is muted and mute period hasn't expired
    if user.muted? && user.banned_until && user.banned_until > Time.current
      return false
    end

    # Reset status if ban/mute period expired
    if user.banned_until && user.banned_until <= Time.current
      user.update!(status: :active, banned_until: nil)
    end

    true
  end

  def self.promote_user(user_id, new_role, promoted_by)
    user = User.find_by(telegram_id: user_id)
    return { success: false, message: "User not found" } unless user

    old_role = user.role
    user.update!(role: new_role)

    ModerationLog.create!(
      user_id: user.telegram_id,
      chat_id: 0, # System action
      action: :promoted,
      reason: "Role changed from #{old_role} to #{new_role}",
      moderator_id: promoted_by,
      details: { old_role: old_role, new_role: new_role }
    )

    { success: true, message: "User #{user.first_name} promoted to #{new_role}" }
  end

  def self.get_user_stats(user_id)
    user = User.find_by(telegram_id: user_id)
    return nil unless user

    {
      username: user.username || user.first_name,
      role: user.role,
      status: user.status,
      message_count: user.message_count,
      warning_count: user.warning_count,
      last_interaction: user.last_interaction,
      member_since: user.created_at,
      recent_messages: user.messages.where('created_at > ?', 24.hours.ago).count,
      flagged_messages: user.messages.flagged.count
    }
  end

  def self.get_chat_stats(chat_id)
    chat = ChatSession.find_by(chat_id: chat_id)
    return nil unless chat

    {
      chat_title: chat.chat_title,
      chat_type: chat.chat_type,
      moderation_enabled: chat.moderation_enabled,
      total_messages: chat.messages.count,
      flagged_messages: chat.messages.flagged.count,
      active_users: chat.messages.where('created_at > ?', 24.hours.ago)
                        .distinct.count(:telegram_user_id),
      settings: chat.settings || {}
    }
  end

  def self.cleanup_expired_bans
    expired_users = User.where('banned_until IS NOT NULL AND banned_until <= ?', Time.current)
    expired_users.update_all(status: 0, banned_until: nil)
    expired_users.count
  end
end
