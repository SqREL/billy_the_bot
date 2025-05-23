class ClaudeInteractionHandler
  class << self
    def handle(message, user, chat_session, text, claude_service, bot, logger)
      query = extract_query(text)
      
      if query.empty?
        send_empty_query_response(bot, message)
        return
      end

      processing_message = send_processing_message(bot, message)

      begin
        response = generate_claude_response(query, user, chat_session, claude_service, logger)
        
        if response && !response.empty?
          handle_successful_response(bot, message, processing_message, response, user, chat_session, query, logger)
        else
          handle_failed_response(bot, message, processing_message)
        end

      rescue => e
        handle_error_response(bot, message, processing_message, e, logger)
      end
    end

    private

    def extract_query(text)
      text.strip
    end

    def send_empty_query_response(bot, message)
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "Питай мене шось, йобана",
        reply_to_message_id: message.message_id
      )
    end

    def send_processing_message(bot, message)
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "Піжди єбать...",
        reply_to_message_id: message.message_id
      )
    end

    def generate_claude_response(query, user, chat_session, claude_service, logger)
      context = build_context(user, chat_session)
      logger.info("Sending to Claude: #{query.length > 100 ? query[0..100] + '...' : query}")
      claude_service.generate_response(query, context)
    end

    def build_context(user, chat_session)
      {
        user_role: user.role,
        chat_type: chat_session.chat_type,
        user_name: user.first_name || user.username || "User",
        user_points: user.points || 0
      }
    end

    def handle_successful_response(bot, message, processing_message, response, user, chat_session, query, logger)
      store_interaction(message, user, chat_session, query, response, logger)
      response_with_points = add_points_reward(response, user, chat_session, logger)
      send_final_response(bot, message, processing_message, response_with_points)
    end

    def store_interaction(message, user, chat_session, query, response, logger)
      begin
        Message.create!(
          telegram_message_id: message.message_id,
          telegram_user_id: user.telegram_id,
          telegram_chat_id: chat_session.chat_id,
          content: query,
          claude_response: response,
          message_type: 'claude_query'
        )
      rescue => e
        logger.error("Failed to store message: #{e.message}")
      end
    end

    def add_points_reward(response, user, chat_session, logger)
      return response unless rand < 0.3 # 30% chance

      begin
        reward = PointsService.reward_activity(user, :helpful_response, chat_session.chat_id)
        if reward && reward > 0
          response += "\n\n✨ +#{reward} points for engaging with Claude!"
        end
      rescue => e
        logger.error("Failed to award points: #{e.message}")
      end

      response
    end

    def send_final_response(bot, message, processing_message, response)
      if response.length > 4000
        send_long_response(bot, message, processing_message, response)
      else
        bot.api.edit_message_text(
          chat_id: message.chat.id,
          message_id: processing_message.message_id,
          text: response
        )
      end
    end

    def send_long_response(bot, message, processing_message, response)
      parts = response.scan(/.{1,4000}/)
      parts.each_with_index do |part, index|
        if index == 0
          bot.api.edit_message_text(
            chat_id: message.chat.id,
            message_id: processing_message.message_id,
            text: part
          )
        else
          bot.api.send_message(
            chat_id: message.chat.id,
            text: part,
            reply_to_message_id: message.message_id
          )
        end
        sleep(0.1)
      end
    end

    def handle_failed_response(bot, message, processing_message)
      bot.api.edit_message_text(
        chat_id: message.chat.id,
        message_id: processing_message.message_id,
        text: "🤖 I couldn't generate a response right now. Please try asking differently."
      )
    end

    def handle_error_response(bot, message, processing_message, error, logger)
      logger.error("Claude response error: #{error.class}: #{error.message}")
      logger.error(error.backtrace.first(5).join("\n"))
      
      error_message = case error.class.to_s
                     when /Timeout/, /Net::TimeoutError/
                       "⏱️ Request timed out. Please try again."
                     when /APIError/, /HTTP/
                       "🔌 AI service temporarily unavailable. Try again in a moment."
                     when /JSON/
                       "📝 Response format error. Please try again."
                     else
                       "🤖 Technical error occurred. Please try again or contact admin."
                     end
      
      begin
        bot.api.edit_message_text(
          chat_id: message.chat.id,
          message_id: processing_message.message_id,
          text: error_message
        )
      rescue => edit_error
        logger.error("Failed to edit error message: #{edit_error.message}")
        begin
          bot.api.send_message(
            chat_id: message.chat.id,
            text: error_message,
            reply_to_message_id: message.message_id
          )
        rescue => send_error
          logger.error("Failed to send error message: #{send_error.message}")
        end
      end
    end
  end
end