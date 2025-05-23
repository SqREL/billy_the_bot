require 'anthropic'

class ClaudeService
  def initialize
    @client = Anthropic::Client.new(api_key: ENV['ANTHROPIC_API_KEY'])
    @model = 'claude-4-sonnet-20250514'
  end

  def generate_response(message, context = {})
    user_message = message.strip
    return nil if user_message.empty?

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

      response.content.first.text
    rescue => e
      puts "Claude API error: #{e.message}"
      "Sorry, I'm having trouble processing your request right now."
    end
  end

  def analyze_content(message)
    return { violence_score: 0, toxicity_score: 0, safe: true } if message.strip.empty?

    begin
      analysis_prompt = build_analysis_prompt(message)
      
      response = @client.messages.create(
        model: @model,
        max_tokens: 500,
        messages: [
          { role: 'user', content: analysis_prompt }
        ]
      )

      result = response.content.first.text
      parse_analysis_result(result)
    rescue => e
      puts "Content analysis error: #{e.message}"
      { violence_score: 0, toxicity_score: 0, safe: true }
    end
  end

  private

  def build_system_prompt(context)
    base_prompt = "You are a helpful AI assistant in a Telegram chat. Be concise and friendly."
    
    if context[:chat_type] == 'group'
      base_prompt += " You're in a group chat, so keep responses brief unless specifically asked for detail."
    end

    if context[:user_role] == 'admin'
      base_prompt += " The user is an admin, so you can provide more technical information if needed."
    end

    base_prompt
  end

  def build_analysis_prompt(message)
    <<~PROMPT
      Analyze this message for violence and toxicity. Return your analysis in JSON format:

      Message: "#{message}"

      Provide scores from 0.0 (completely safe) to 1.0 (extremely problematic):
      - violence_score: How violent or threatening is the content?
      - toxicity_score: How toxic, offensive, or harmful is the content?
      - safe: Boolean indicating if the message is safe for a public chat

      Consider context and intent. Mild profanity might have low toxicity if not directed at someone.
      
      Respond only with valid JSON in this format:
      {"violence_score": 0.0, "toxicity_score": 0.0, "safe": true}
    PROMPT
  end

  def parse_analysis_result(result)
    begin
      parsed = JSON.parse(result)
      {
        violence_score: parsed['violence_score'].to_f,
        toxicity_score: parsed['toxicity_score'].to_f,
        safe: parsed['safe']
      }
    rescue JSON::ParserError
      # Fallback parsing if JSON is malformed
      violence_match = result.match(/violence_score['":]?\s*([0-9.]+)/)
      toxicity_match = result.match(/toxicity_score['":]?\s*([0-9.]+)/)
      safe_match = result.match(/safe['":]?\s*(true|false)/)

      {
        violence_score: violence_match ? violence_match[1].to_f : 0.0,
        toxicity_score: toxicity_match ? toxicity_match[1].to_f : 0.0,
        safe: safe_match ? safe_match[1] == 'true' : true
      }
    end
  end
end
