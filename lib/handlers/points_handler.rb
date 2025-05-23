class PointsHandler
  def initialize(bot)
    @bot = bot
  end

  def handle_points_command(message, user, chat_session, command, args)
    command_handlers = {
      '/points' => -> { handle_points_info(message, user, args) },
      '/give' => -> { handle_give_points(message, user, chat_session, args) },
      '/leaderboard' => -> { handle_leaderboard(message, chat_session, args) },
      '/top' => -> { handle_leaderboard(message, chat_session, args) },
      '/daily' => -> { handle_daily_bonus(message, user, chat_session) },
      '/transfer' => -> { handle_transfer_points(message, user, args) }
    }

    handler = command_handlers[command]
    handler ? handler.call : false
  end

  private

  def handle_points_info(message, user, args)
    if args.empty?
      # Show own points
      show_user_points(message, user)
    else
      # Show someone else's points (if admin/moderator)
      return send_error(message, "You don't have permission to view other users' points") unless user.admin? || user.moderator?
      
      username = extract_username(args[0])
      target_user = User.find_by(username: username)
      return send_error(message, "User not found") unless target_user

      show_user_points(message, target_user)
    end
    true
  end

  def handle_give_points(message, user, chat_session, args)
    return send_error(message, "Only admins and moderators can give points") unless user.admin? || user.moderator?
    return send_error(message, "Usage: /give @username amount [reason]") if args.length < 2

    username = extract_username(args[0])
    amount = args[1].to_i
    reason = args[2..].join(' ') || "Points given by #{user.display_name}"

    return send_error(message, "Invalid amount") if amount <= 0 || amount > 1000

    target_user = User.find_by(username: username)
    return send_error(message, "User not found") unless target_user

    result = PointsService.award_points(target_user, amount, reason, user.telegram_id, chat_session.chat_id)
    
    if result[:success]
      response = "✅ #{result[:message]}\n💰 New balance: #{result[:new_total]} points"
      send_response(message, response)
      
      # Notify the recipient if in group chat
      if chat_session.chat_type != 'private'
        notify_user_points_awarded(target_user, amount, reason, user.display_name)
      end
    else
      send_error(message, result[:message])
    end
    
    true
  end

  def handle_leaderboard(message, chat_session, args)
    chat_only = args.include?('chat') || chat_session.chat_type != 'private'
    limit = 10

    leaderboard = if chat_only && chat_session.chat_type != 'private'
                   PointsService.get_leaderboard(chat_session.chat_id, limit)
                 else
                   PointsService.get_leaderboard(nil, limit)
                 end

    response = format_leaderboard(leaderboard, chat_only)
    send_response(message, response)
    true
  end

  def handle_daily_bonus(message, user, chat_session)
    # Check if user already claimed today
    today_bonus = user.point_transactions
                     .where(transaction_type: :activity_bonus)
                     .where('created_at >= ?', Date.current.beginning_of_day)
                     .where('reason LIKE ?', '%daily bonus%')
                     .exists?

    if today_bonus
      send_response(message, "🎁 You've already claimed your daily bonus today!\nCome back tomorrow for more points.")
      return true
    end

    bonus_amount = PointsService.calculate_daily_bonus(user)
    
    PointTransaction.create!(
      user_id: user.telegram_id,
      chat_id: chat_session.chat_id,
      amount: bonus_amount,
      transaction_type: :activity_bonus,
      reason: "Daily bonus"
    )

    user.update!(
      points: user.points + bonus_amount,
      total_points_earned: user.total_points_earned + bonus_amount
    )

    response = format_daily_bonus_message(user, bonus_amount)
    send_response(message, response)
    true
  end

  def handle_transfer_points(message, user, args)
    return send_error(message, "Usage: /transfer @username amount [reason]") if args.length < 2

    username = extract_username(args[0])
    amount = args[1].to_i
    reason = args[2..].join(' ') || "Point transfer"

    return send_error(message, "Invalid amount") if amount <= 0
    return send_error(message, "Minimum transfer amount is 10 points") if amount < 10
    return send_error(message, "Maximum transfer amount is 500 points") if amount > 500

    target_user = User.find_by(username: username)
    return send_error(message, "User not found") unless target_user

    result = PointsService.transfer_points(user, target_user, amount, reason)
    
    if result[:success]
      send_response(message, "✅ #{result[:message]}")
      
      # Notify recipient
      notify_user_points_received(target_user, amount, user.display_name, reason)
    else
      send_error(message, result[:message])
    end
    
    true
  end

  def show_user_points(message, user)
    rank = PointsService.get_user_rank(user)
    recent_activity = user.recent_points_activity(7)
    
    response = <<~POINTS
      💰 Points Summary for #{user.display_name}

      🏆 Current Points: #{user.points}
      📊 Rank: ##{rank}
      📈 Total Earned: #{user.total_points_earned}
      📉 Total Spent: #{user.total_points_spent}

      📅 Recent Activity (7 days):
    POINTS

    if recent_activity.any?
      recent_activity.first(5).each do |transaction|
        emoji = transaction.amount > 0 ? '📈' : '📉'
        response += "#{emoji} #{transaction.amount > 0 ? '+' : ''}#{transaction.amount} - #{transaction.reason}\n"
      end
      
      if recent_activity.count > 5
        response += "... and #{recent_activity.count - 5} more\n"
      end
    else
      response += "No recent activity\n"
    end

    response += "\n💡 Use /daily for daily bonus!"
    
    send_response(message, response)
  end

  def format_leaderboard(leaderboard, chat_only = false)
    title = chat_only ? "🏆 Chat Leaderboard" : "🏆 Global Leaderboard"
    
    response = "#{title}\n\n"
    
    if leaderboard.any?
      leaderboard.each_with_index do |user, index|
        medal = case index
                when 0 then '🥇'
                when 1 then '🥈'
                when 2 then '🥉'
                else "#{index + 1}."
                end
        
        response += "#{medal} #{user.display_name} - #{user.points} points\n"
      end
    else
      response += "No users found."
    end

    response += "\n💡 Earn points by being active in chat!"
    response
  end

  def format_daily_bonus_message(user, bonus_amount)
    consecutive_days = calculate_consecutive_days(user)
    
    response = <<~BONUS
      🎁 Daily Bonus Claimed!

      💰 You earned: #{bonus_amount} points
      🔥 Streak: #{consecutive_days} days
      🏆 Total Points: #{user.points}

    BONUS

    # Add streak milestones
    case consecutive_days
    when 7
      response += "🎉 7-day streak bonus! Keep it up!"
    when 14
      response += "🔥 Two weeks strong! Amazing dedication!"
    when 30
      response += "👑 One month streak! You're a legend!"
    end

    response += "\n\n💡 Come back tomorrow for more points!"
    response
  end

  def calculate_consecutive_days(user)
    days = 0
    current_date = Date.current

    loop do
      break unless user.messages.where('DATE(created_at) = ?', current_date - days.days).exists?
      days += 1
      break if days > 365 # Reasonable limit
    end

    days
  end

  def notify_user_points_awarded(user, amount, reason, admin_name)
    # This would send a private message to the user
    # Implementation depends on how you want to handle notifications
  end

  def notify_user_points_received(user, amount, sender_name, reason)
    # This would send a private message to the user
    # Implementation depends on how you want to handle notifications
  end

  def extract_username(text)
    text.start_with?('@') ? text[1..] : text
  end

  def send_response(message, text)
    @bot.api.send_message(
      chat_id: message.chat.id,
      text: text,
      reply_to_message_id: message.message_id,
      parse_mode: 'HTML'
    )
  end

  def send_error(message, text)
    @bot.api.send_message(
      chat_id: message.chat.id,
      text: "❌ #{text}",
      reply_to_message_id: message.message_id
    )
  end
end
