FactoryBot.define do
  factory :user do
    sequence(:telegram_id) { |n| n + 100000 }
    sequence(:username) { |n| "user#{n}" }
    sequence(:first_name) { |n| "User #{n}" }
    last_name { "Test" }
    role { :user }
    status { :active }
    points { 0 }
    total_points_earned { 0 }
    total_points_spent { 0 }
    warning_count { 0 }
    message_count { 0 }
    language_code { 'en' }
    
    trait :admin do
      role { :admin }
    end
    
    trait :moderator do
      role { :moderator }
    end
    
    trait :banned do
      status { :banned }
      banned_until { 1.day.from_now }
    end
    
    trait :muted do
      status { :muted }
      banned_until { 1.hour.from_now }
    end
  end

  factory :chat_session do
    sequence(:chat_id) { |n| -n }
    chat_type { 'supergroup' }
    sequence(:chat_title) { |n| "Test Chat #{n}" }
    moderation_enabled { true }
    settings { {} }
  end

  factory :message do
    association :user
    association :chat_session
    telegram_message_id { rand(1000..9999) }
    telegram_user_id { user.telegram_id }
    telegram_chat_id { chat_session.chat_id }
    content { "Test message" }
    message_type { 'text' }
    flagged { false }
    
    trait :flagged do
      flagged { true }
    end
    
    trait :violent do
      violence_score { 0.9 }
    end
    
    trait :toxic do
      toxicity_score { 0.8 }
    end
  end

  factory :point_transaction do
    association :user
    association :chat_session
    user_id { user.telegram_id }
    chat_id { chat_session.chat_id }
    amount { 10 }
    transaction_type { :earned }
    reason { "Test transaction" }
  end

  factory :moderation_log do
    association :user
    association :chat_session
    user_id { user.telegram_id }
    chat_id { chat_session.chat_id }
    action { :warned }
    reason { "Test moderation action" }
  end

  factory :message_template do
    name { "Test Template" }
    content { "Test template content" }
    template_type { :text }
    active { true }
  end

  factory :admin_session do
    sequence(:session_id) { |n| "session_#{n}" }
    sequence(:username) { |n| "admin#{n}" }
    sequence(:ip_address) { |n| "127.0.0.#{n}" }
    expires_at { 24.hours.from_now }
  end
end