FactoryBot.define do
  factory :admin_session do
    sequence(:session_id) { |n| "session_#{n}" }
    sequence(:username) { |n| "admin#{n}" }
    sequence(:ip_address) { |n| "127.0.0.#{n}" }
    expires_at { 24.hours.from_now }
  end
end
