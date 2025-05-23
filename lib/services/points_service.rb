class PointsService
  # Point rewards for different activities
  ACTIVITY_REWARDS = {
    message_sent: 1,
    helpful_response: 5,
    daily_activity: 10,
    week_streak: 50,
    month_streak: 200
  }.freeze

  def self.award_points(user, amount, reason, admin_id = nil, chat_id = 0)
    return { success: false, message: "Invalid amount" } if amount <= 0

    begin
      user.add_points(amount, reason, admin_id, chat_id)
      
      # Log moderation action if done by admin
      if admin_id
        ModerationLog.create!(
          user_id: user.telegram_id,
          chat_id: chat_id,
          action: :points_given,
          reason: reason,
          moderator_id: admin_id,
          details: { amount: amount }
        )
      end

      { success: true, message: "Awarded #{amount} points to #{user.display_name}", new_total: user.points }
    rescue => e
      { success: false, message: "Error awarding points: #{e.message}" }
    end
  end

  def self.deduct_points(user, amount, reason, admin_id = nil, chat_id = 0)
    return { success: false, message: "Invalid amount" } if amount <= 0
    return { success: false, message: "Insufficient points" } if user.points < amount

    begin
      user.add_points(-amount, reason, admin_id, chat_id)
      
      # Log moderation action if done by admin
      if admin_id
        ModerationLog.create!(
          user_id: user.telegram_id,
          chat_id: chat_id,
          action: :points_taken,
          reason: reason,
          moderator_id: admin_id,
          details: { amount: amount }
        )
      end

      { success: true, message: "Deducted #{amount} points from #{user.display_name}", new_total: user.points }
    rescue => e
      { success: false, message: "Error deducting points: #{e.message}" }
    end
  end

  def self.reward_activity(user, activity_type, chat_id = 0)
    reward = ACTIVITY_REWARDS[activity_type.to_sym]
    return unless reward

    # Prevent spam rewards (max once per hour for message rewards)
    if activity_type == :message_sent
      recent_reward = user.point_transactions
                         .where(transaction_type: :message_reward)
                         .where('created_at > ?', 1.hour.ago)
                         .exists?
      return if recent_reward
    end

    PointTransaction.create!(
      user_id: user.telegram_id,
      chat_id: chat_id,
      amount: reward,
      transaction_type: activity_type == :message_sent ? :message_reward : :activity_bonus,
      reason: "#{activity_type.to_s.humanize} reward"
    )

    user.update!(
      points: user.points + reward,
      total_points_earned: user.total_points_earned + reward
    )

    reward
  end

  def self.get_leaderboard(chat_id = nil, limit = 10)
    query = User.where('points > 0')
               .order('points DESC')
               .limit(limit)

    # If chat_id is specified, we could filter by users who have been active in that chat
    # but for now, let's just return global leaderboard
    query
  end

  def self.get_user_rank(user, chat_id = nil)
    # Simple ranking based on points, ignoring chat_id for now
    better_users = User.where('points > ?', user.points || 0).count
    better_users + 1
  end

  def self.transfer_points(from_user, to_user, amount, reason = "Point transfer")
    return { success: false, message: "Invalid amount" } if amount <= 0
    return { success: false, message: "Insufficient points" } if from_user.points < amount
    return { success: false, message: "Cannot transfer to yourself" } if from_user.telegram_id == to_user.telegram_id

    begin
      ActiveRecord::Base.transaction do
        # Deduct from sender
        from_user.update!(points: from_user.points - amount, total_points_spent: from_user.total_points_spent + amount)
        PointTransaction.create!(
          user_id: from_user.telegram_id,
          chat_id: 0,
          amount: -amount,
          transaction_type: :spent,
          reason: "Transfer to #{to_user.display_name}: #{reason}"
        )

        # Add to receiver
        to_user.update!(points: to_user.points + amount, total_points_earned: to_user.total_points_earned + amount)
        PointTransaction.create!(
          user_id: to_user.telegram_id,
          chat_id: 0,
          amount: amount,
          transaction_type: :earned,
          reason: "Transfer from #{from_user.display_name}: #{reason}"
        )
      end

      { success: true, message: "Transferred #{amount} points from #{from_user.display_name} to #{to_user.display_name}" }
    rescue => e
      { success: false, message: "Transfer failed: #{e.message}" }
    end
  end

  def self.calculate_daily_bonus(user)
    # Calculate consecutive days of activity
    days_active = 0
    current_date = Date.current

    loop do
      break unless user.messages.where('DATE(created_at) = ?', current_date - days_active.days).exists?
      days_active += 1
      break if days_active > 30 # Max check 30 days
    end

    case days_active
    when 1..6
      days_active * 5  # 5 points per day
    when 7..13
      35 + ((days_active - 7) * 10)  # Week bonus + 10 per day
    when 14..29
      105 + ((days_active - 14) * 15)  # Two week bonus + 15 per day
    else
      330  # Month+ bonus (capped)
    end
  end
end
