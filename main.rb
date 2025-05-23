#!/usr/bin/env ruby

require 'telegram/bot'
require 'anthropic'
require 'logger'
require 'pry'

# Configure logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# Environment variables
TELEGRAM_TOKEN = ENV["BILLY_TELEGRAM_TOKEN"]
ANTHROPIC_API_KEY = ENV["BILLY_ANTROPIC_API_KEY"]
BOT_USERNAME = ENV["BILLY_BOT_NAME"]

# Initialize Claude client
claude = Anthropic::Client.new(access_token: ANTHROPIC_API_KEY)

# Start the bot
Telegram::Bot::Client.run(TELEGRAM_TOKEN) do |bot|
  logger.info('Bot started')

  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      # Handle /start command
      if message.text == '/start'
        bot.api.send_message(
          chat_id: message.chat.id,
          text: "Hi! I'm a bot integrated with Claude. Tag me with @#{BOT_USERNAME} in any message to get a response."
        )
      
      # Handle /help command
      elsif message.text == '/help'
        bot.api.send_message(
          chat_id: message.chat.id,
          text: "Tag me with @#{BOT_USERNAME} followed by your question to get a response from Claude."
        )
      
      # Handle messages that mention the bot
      elsif message.text && message.text.include?("@#{BOT_USERNAME}")
        # Extract the query (everything after the bot's username)
        query = message.text.split("@#{BOT_USERNAME}", 2)[1].to_s.strip
        
        if !query.empty?
          # Let user know the bot is processing
          processing_message = bot.api.send_message(
            chat_id: message.chat.id,
            text: "Thinking..."
          )
          
          begin
            # Call Claude API - correct syntax for Ruby anthropic gem
            response = claude.messages(parameters: {
              model: "claude-3-7-sonnet-20250219", # Use the appropriate model
              max_tokens: 1000,
              messages: [
                { role: "user", content: query }
              ]
            })
            
            # Get Claude's response - the structure depends on your gem version
            # Try one of these approaches:
            #claude_response = response.content
            # If that doesn't work:
            # claude_response = response.responses.first.text
            # Or:
            claude_response = response['content'].first['text']
             
            
            # Edit the "processing" message with Claude's response
            bot.api.edit_message_text(
              chat_id: message.chat.id,
              message_id: processing_message.message_id,
              text: claude_response
            )
          rescue => e
            logger.error("Error: #{e.message}")
            
            # Edit the "processing" message with error information
            bot.api.edit_message_text(
              chat_id: message.chat.id,
              message_id: processing_messagemessage_id,
              text: "Sorry, I encountered an error: #{e.message}"
            )
          end
        else
          # If no query is provided after the tag
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "Please provide a question after tagging me."
          )
        end
      end
    end
  end
end
