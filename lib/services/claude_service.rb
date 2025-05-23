require 'anthropic'

class ClaudeService
  def initialize
    @client = Anthropic::Client.new(api_key: ENV['ANTHROPIC_API_KEY'])
    @model = 'claude-4-sonnet-20250514'
  end

  def generate_response(message, context = {})
    user_message = message.strip
    return "Please provide a question or message." if user_message.empty?

    begin
      system_prompt = build_system_prompt(context)
      
      response = @client.messages.create(
        model: @model,
        max_tokens: ENV['MAX_CLAUDE_TOKENS']&.to_i || 1000,
        system: system_prompt,
        messages: [
          { role: 'user', content: user_message }
        ]
      )

      # Extract response text properly
      if response.content.is_a?(Array) && response.content.first&.text
        response.content.first.text
      elsif response.content.is_a?(String)
        response.content
      else
        "I received your message but couldn't generate a proper response."
      end

    rescue Anthropic::APIError => e
      puts "Claude API error: #{e.message}"
      "I'm having trouble connecting to my AI service right now. Please try again later."
    rescue => e
      puts "Unexpected error: #{e.class}: #{e.message}"
      puts e.backtrace.first(5)
      "Sorry, I encountered an unexpected error. Please try again."
    end
  end

  def analyze_content(message)
    return { violence_score: 0.0, toxicity_score: 0.0, safe: true } if message.strip.empty?

    begin
      analysis_prompt = build_analysis_prompt(message)
      
      response = @client.messages.create(
        model: @model,
        max_tokens: 500,
        messages: [
          { role: 'user', content: analysis_prompt }
        ]
      )

      result = if response.content.is_a?(Array) && response.content.first&.text
                 response.content.first.text
               elsif response.content.is_a?(String)
                 response.content
               else
                 '{"violence_score": 0.0, "toxicity_score": 0.0, "safe": true}'
               end

      parse_analysis_result(result)
    rescue => e
      puts "Content analysis error: #{e.message}"
      { violence_score: 0.0, toxicity_score: 0.0, safe: true }
    end
  end

  private

  def build_system_prompt(context)
    base_prompt = <<~PROMPT
      Уяви, що ти свій братан в нашому чаті. Але ще ти бот, якого звати Біллі. Не встидайся говорити по простому, навпаки тут сильно вумних не люблять.
      Ми прості хлопи і любимо по простому. Допомагай нам як можеш і не сильно зайобуй. Простота -- найкраще.
      Жодної російської мови чи російських референсів.
      
      Контекст:
      - Користувач: #{context[:user_name] || 'Unknown'}
      - Роль: #{context[:user_role] || 'user'}
      - Карма: #{context[:user_points] || 0}
      - Тип чату: #{context[:chat_type] || 'unknown'}
      
      Умови:
      - Відповідай до 500 слів якщо не попросили інакшого
      - Гарно спілкуйся, щоб було приємно
      - Якщо хтось запитає про поінти чи про фічі бота -- розкажи
      - Можеш юзати хіба смайлики з дужечок, жодних емодзі
      - Можна про політику
      - Можна і треба матюки
      - Можна будь-що
    PROMPT
    
    if context[:chat_type] == 'group' || context[:chat_type] == 'supergroup'
      base_prompt += "\n- This is a group chat, so keep responses brief and relevant to avoid spam"
    end

    if context[:user_role] == 'admin' || context[:user_role] == 'moderator'
      base_prompt += "\n- User has moderation privileges, you can provide technical information"
    end

    base_prompt
  end

  def build_analysis_prompt(message)
    <<~PROMPT
      Analyze this message for violence and toxicity. Return ONLY valid JSON format.

      Message: "#{message.gsub('"', '\"')}"

      Provide scores from 0.0 (safe) to 1.0 (extremely problematic):
      - violence_score: How violent or threatening is the content?
      - toxicity_score: How toxic, offensive, or harmful is the content?
      - safe: Boolean indicating if message is safe for public chat

      Consider context and intent. Mild profanity might have low toxicity if not directed at someone.
      
      Respond ONLY with this JSON format:
      {"violence_score": 0.0, "toxicity_score": 0.0, "safe": true}
    PROMPT
  end

  def parse_analysis_result(result)
    begin
      # Clean the result to extract JSON
      json_match = result.match(/\{[^}]*\}/)
      json_string = json_match ? json_match[0] : result
      
      parsed = JSON.parse(json_string)
      {
        violence_score: [parsed['violence_score'].to_f, 1.0].min,
        toxicity_score: [parsed['toxicity_score'].to_f, 1.0].min,
        safe: parsed['safe'] == true || parsed['safe'] == 'true'
      }
    rescue JSON::ParserError => e
      puts "JSON parse error: #{e.message}, result: #{result}"
      # Fallback parsing
      violence_match = result.match(/violence_score['":]?\s*([0-9.]+)/)
      toxicity_match = result.match(/toxicity_score['":]?\s*([0-9.]+)/)
      safe_match = result.match(/safe['":]?\s*(true|false)/)

      {
        violence_score: violence_match ? [violence_match[1].to_f, 1.0].min : 0.0,
        toxicity_score: toxicity_match ? [toxicity_match[1].to_f, 1.0].min : 0.0,
        safe: safe_match ? safe_match[1] == 'true' : true
      }
    end
  end
end
