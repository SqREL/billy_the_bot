FactoryBot.define do
  factory :user do
    sequence(:telegram_id) { |n| n }
    sequence(:username) { |n| "user#{n}" }
    sequence(:first_name) { |n| "User #{n}" }
    role { :user }
    status { :active }
    points { 0 }
    warning_count { 0 }
    language_code { 'en' }
  end
end
