require 'telegram/bot'
require 'logger'

class BotManager
  attr_reader :logger, :bot_client

  def initialize
    @logger = setup_logger
    @bot_token = ENV["BILLY_TELEGRAM_TOKEN"]
    @bot_username = ENV["BILLY_BOT_NAME"]
    
    validate_environment
    initialize_services
  end

  def start
    logger.info("Bot starting with Claude 4 Sonnet and Web Admin UI...")
    
    Telegram::Bot::Client.run(@bot_token) do |bot|
      @bot_client = bot
      @message_handler = MessageHandler.new(bot, @services, logger)
      
      logger.info('✅ Bot started successfully')
      
      bot.listen do |message|
        @message_handler.handle_message(message)
      end
    end
  end

  private

  def setup_logger
    logger = Logger.new(STDOUT)
    logger.level = Logger.const_get(ENV['LOG_LEVEL'] || 'INFO')
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    logger
  end

  def validate_environment
    logger.info("=== Bot Starting ===")
    logger.info("- BILLY_TELEGRAM_TOKEN: #{@bot_token ? 'SET' : 'NOT SET'}")
    logger.info("- ANTHROPIC_API_KEY: #{ENV['ANTHROPIC_API_KEY'] ? 'SET' : 'NOT SET'}")
    logger.info("- BILLY_BOT_NAME: #{@bot_username}")

    unless @bot_token && @bot_username
      logger.error("Missing required environment variables")
      exit 1
    end
  end

  def initialize_services
    logger.info("Initializing services...")
    
    begin
      claude_service = ClaudeService.new
      logger.info("✅ Claude service initialized")
    rescue => e
      logger.error("❌ Failed to initialize Claude service: #{e.message}")
      claude_service = nil
    end

    @services = {
      claude: claude_service,
      moderation: ModerationService.new(claude_service),
      rate_limiter: RateLimiter.new,
      admin_handler: nil, # Will be initialized with bot instance
      points_handler: nil # Will be initialized with bot instance
    }
  end
end