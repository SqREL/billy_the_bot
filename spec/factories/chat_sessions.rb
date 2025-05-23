FactoryBot.define do
  factory :chat_session do
    sequence(:chat_id) { |n| -n } # Telegram group chat IDs are negative
    sequence(:chat_title) { |n| "Test Chat #{n}" }
    moderation_enabled { true }
    settings { {} }
  end
end
