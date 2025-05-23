class CommandHandlers
  class << self
    def handle_start(message, user, bot)
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

    def handle_help(message, user, bot)
      help_text = build_help_text(user)
      
      bot.api.send_message(
        chat_id: message.chat.id,
        text: help_text,
        reply_to_message_id: message.message_id
      )
    end

    def handle_status(message, user, bot)
      status_text = build_status_text(user)
      
      bot.api.send_message(
        chat_id: message.chat.id,
        text: status_text,
        reply_to_message_id: message.message_id
      )
    end

    private

    def build_help_text(user)
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
        help_text += build_moderator_help
      end

      if user.admin?
        help_text += build_admin_help
      end

      help_text
    end

    def build_moderator_help
      <<~TEXT
        🛡️ Moderator Commands:
        • /ban @user [reason] - Ban a user
        • /unban @user - Unban a user
        • /mute @user [hours] [reason] - Mute a user
        • /warn @user [reason] - Warn a user
        • /stats [@user] - Show user or chat stats
        • /moderation [on|off|settings] - Manage moderation

      TEXT
    end

    def build_admin_help
      <<~TEXT
        👑 Admin Commands:
        • /promote @user [moderator|admin] - Promote user
        • /demote @user - Demote user to regular user
        • /cleanup - Clean up expired bans

        🌐 Web Admin Panel:
        Access the web admin panel at: http://your-server:3000
        Username: admin | Password: (check your .env file)

      TEXT
    end

    def build_status_text(user)
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

      status_text
    end
  end
end