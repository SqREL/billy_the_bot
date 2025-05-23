require 'redis'

class RateLimiter
  def initialize
    @redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379')
  rescue Redis::CannotConnectError
    @redis = nil
    puts "Warning: Redis not available, rate limiting disabled"
  end

  def check_rate_limit(user_id, chat_id)
    return true unless @redis # Allow if Redis unavailable

    current_time = Time.now.to_i
    minute_key = "rate_limit:#{user_id}:#{chat_id}:#{current_time / 60}"
    hour_key = "rate_limit:#{user_id}:#{chat_id}:#{current_time / 3600}"

    begin
      # Check minute limit
      minute_count = @redis.incr(minute_key)
      @redis.expire(minute_key, 60) if minute_count == 1

      if minute_count > (ENV['MAX_MESSAGES_PER_MINUTE']&.to_i || 10)
        return false
      end

      # Check hour limit
      hour_count = @redis.incr(hour_key)
      @redis.expire(hour_key, 3600) if hour_count == 1

      if hour_count > (ENV['MAX_MESSAGES_PER_HOUR']&.to_i || 100)
        return false
      end

      true
    rescue Redis::BaseError => e
      puts "Redis error in rate limiter: #{e.message}"
      true # Allow on Redis errors
    end
  end

  def get_remaining_limit(user_id, chat_id)
    return { minute: 999, hour: 999 } unless @redis

    current_time = Time.now.to_i
    minute_key = "rate_limit:#{user_id}:#{chat_id}:#{current_time / 60}"
    hour_key = "rate_limit:#{user_id}:#{chat_id}:#{current_time / 3600}"

    begin
      minute_used = @redis.get(minute_key).to_i
      hour_used = @redis.get(hour_key).to_i

      {
        minute: [(ENV['MAX_MESSAGES_PER_MINUTE']&.to_i || 10) - minute_used, 0].max,
        hour: [(ENV['MAX_MESSAGES_PER_HOUR']&.to_i || 100) - hour_used, 0].max
      }
    rescue Redis::BaseError
      { minute: 999, hour: 999 }
    end
  end

  def reset_user_limits(user_id)
    return unless @redis

    begin
      pattern = "rate_limit:#{user_id}:*"
      keys = @redis.keys(pattern)
      @redis.del(*keys) if keys.any?
    rescue Redis::BaseError => e
      puts "Redis error resetting limits: #{e.message}"
    end
  end
end
