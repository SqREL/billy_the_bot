class BackgroundTasks
  def self.start(logger)
    Thread.new do
      loop do
        begin
          run_cleanup_tasks(logger)
          run_activity_rewards(logger)
          
          sleep 3600 # Run every hour
        rescue => e
          logger.error("Background task error: #{e.message}")
        end
      end
    end
  end

  private

  def self.run_cleanup_tasks(logger)
    logger.debug("Running cleanup tasks...")
    
    # Clean up expired sessions and bans
    UserService.cleanup_expired_bans
    AdminSession.cleanup_expired
    
    logger.debug("Cleanup tasks completed")
  end

  def self.run_activity_rewards(logger)
    logger.debug("Processing activity rewards...")
    
    # Award daily bonuses for very active users
    active_users = User.joins(:messages)
                      .where('messages.created_at > ?', 1.hour.ago)
                      .group('users.telegram_id')
                      .having('COUNT(messages.id) >= 10')
    
    active_users.each do |user|
      begin
        PointsService.reward_activity(user, :daily_activity)
      rescue => e
        logger.error("Failed to reward user #{user.telegram_id}: #{e.message}")
      end
    end
    
    logger.debug("Activity rewards processed for #{active_users.count} users")
  end
end