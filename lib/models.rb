require 'active_record'

class User < ActiveRecord::Base
  enum :role, { user: 0, moderator: 1, admin: 2 }
  enum :status, { active: 0, warned: 1, muted: 2, banned: 3 }

  has_many :messages, foreign_key: :telegram_user_id, primary_key: :telegram_id
  has_many :moderation_logs, foreign_key: :user_id, primary_key: :telegram_id
  has_many :point_transactions, foreign_key: :user_id, primary_key: :telegram_id

  def banned?
    status == 'banned' && (banned_until.nil? || banned_until > Time.current)
  end

  def muted?
    status == 'muted' && banned_until && banned_until > Time.current
  end

  def can_send_messages?
    active? && !banned?
  end

  def increment_warnings!
    self.warning_count += 1
    case warning_count
    when 1
      update!(status: :warned)
    when 2
      update!(status: :muted, banned_until: 1.hour.from_now)
    when 3
      update!(status: :banned, banned_until: 24.hours.from_now)
    else
      update!(status: :banned, banned_until: nil) # permanent
    end
  end

  def add_points(amount, reason, admin_id = nil, chat_id = 0)
    transaction do
      self.points += amount
      self.total_points_earned += amount if amount > 0
      self.total_points_spent += amount.abs if amount < 0
      save!

      PointTransaction.create!(
        user_id: telegram_id,
        chat_id: chat_id,
        amount: amount,
        transaction_type: amount > 0 ? 'admin_given' : 'admin_taken',
        reason: reason,
        admin_id: admin_id
      )
    end
  end

  def recent_points_activity(days = 30)
    point_transactions.where('created_at > ?', days.days.ago)
                     .order(created_at: :desc)
                     .limit(20)
  end

  def display_name
    username.present? ? "@#{username}" : first_name || "User #{telegram_id}"
  end
end

class ChatSession < ActiveRecord::Base
  self.primary_key = :chat_id

  has_many :messages, foreign_key: :telegram_chat_id, primary_key: :chat_id
  has_many :point_transactions, foreign_key: :chat_id, primary_key: :chat_id

  def moderation_enabled?
    moderation_enabled
  end

  def get_setting(key, default = nil)
    return default unless settings
    settings[key.to_s] || default
  end

  def set_setting(key, value)
    self.settings ||= {}
    self.settings[key.to_s] = value
    save!
  end

  def display_name
    chat_title || "Chat #{chat_id}"
  end
end

class Message < ActiveRecord::Base
  belongs_to :user, foreign_key: :telegram_user_id, primary_key: :telegram_id
  belongs_to :chat_session, foreign_key: :telegram_chat_id, primary_key: :chat_id

  scope :flagged, -> { where(flagged: true) }
  scope :recent, -> { where('created_at > ?', 1.hour.ago) }

  def violent?
    violence_score && violence_score > ENV['VIOLENCE_THRESHOLD'].to_f
  end

  def toxic?
    toxicity_score && toxicity_score > ENV['TOXICITY_THRESHOLD'].to_f
  end
end

class ModerationLog < ActiveRecord::Base
  belongs_to :user, foreign_key: :user_id, primary_key: :telegram_id
  belongs_to :chat_session, foreign_key: :chat_id, primary_key: :chat_id
  belongs_to :message, optional: true

  enum :action, {
    warned: 0,
    muted: 1,
    banned: 2,
    deleted_message: 3,
    unbanned: 4,
    promoted: 5,
    demoted: 6,
    points_given: 7,
    points_taken: 8,
    kicked: 9
  }
end

class PointTransaction < ActiveRecord::Base
  belongs_to :user, foreign_key: :user_id, primary_key: :telegram_id
  belongs_to :chat_session, foreign_key: :chat_id, primary_key: :chat_id, optional: true
  belongs_to :admin_user, class_name: 'User', foreign_key: :admin_id, primary_key: :telegram_id, optional: true

  enum :transaction_type, {
    earned: 0,
    spent: 1,
    admin_given: 2,
    admin_taken: 3,
    message_reward: 4,
    activity_bonus: 5
  }

  scope :recent, -> { where('created_at > ?', 30.days.ago) }
end

class MessageTemplate < ActiveRecord::Base
  belongs_to :creator, class_name: 'User', foreign_key: :created_by, primary_key: :telegram_id, optional: true

  enum :template_type, {
    text: 0,
    poll: 1,
    quiz: 2,
    photo: 3,
    announcement: 4
  }

  scope :active, -> { where(active: true) }

  def parsed_options
    return [] unless options.present?
    JSON.parse(options) rescue []
  end

  def set_options(options_array)
    self.options = options_array.to_json
  end
end

class AdminSession < ActiveRecord::Base
  def self.cleanup_expired
    where('expires_at < ?', Time.current).delete_all
  end

  def expired?
    expires_at < Time.current
  end

  def extend_session!(hours = 24)
    update!(expires_at: hours.hours.from_now)
  end
end
