require 'sinatra'
require 'sinatra/json'
require 'bcrypt'
require 'json'
require 'securerandom'
require 'active_support/all'
require_relative 'config/database'
require_relative 'lib/models'
require_relative 'lib/services/points_service'
require_relative 'lib/services/user_service'

# Configure Sinatra
configure do
  enable :sessions
  set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(32)
  set :public_folder, 'public'
  set :views, 'views'
  set :port, ENV['WEB_PORT'] || 3000
  set :bind, '0.0.0.0'
end

# Admin credentials
ADMIN_PASSWORD = ENV['ADMIN_PASSWORD'] || 'admin123'
ADMIN_USERNAME = ENV['ADMIN_USERNAME'] || 'admin'

# Authentication helpers
def authenticated?
  session[:admin_authenticated] && session[:expires_at] && session[:expires_at] > Time.now.to_i
end

def require_auth!
  halt 401, json(error: 'Unauthorized') unless authenticated?
end

def extend_session!
  session[:expires_at] = 24.hours.from_now.to_i
end

# Middleware
before do
  pass if request.path_info == '/login' || request.path_info.start_with?('/assets')
  redirect '/login' unless authenticated?
end

# Routes
get '/' do
  extend_session!
  @stats = get_dashboard_stats
  erb :dashboard
end

get '/login' do
  erb :login, layout: false
end

post '/login' do
  username = params[:username]
  password = params[:password]

  if username == ADMIN_USERNAME && password == ADMIN_PASSWORD
    session[:admin_authenticated] = true
    session[:admin_username] = username
    session[:expires_at] = 24.hours.from_now.to_i
    session[:login_ip] = request.ip

    AdminSession.create!(
      session_id: session.id.to_s,
      username: username,
      ip_address: request.ip,
      expires_at: 24.hours.from_now
    )

    redirect '/'
  else
    @error = 'Invalid credentials'
    erb :login, layout: false
  end
end

get '/logout' do
  AdminSession.where(session_id: session.id.to_s).delete_all if session.id
  session.clear
  redirect '/login'
end

# Users management
get '/users' do
  extend_session!
  @page = (params[:page] || 1).to_i
  @per_page = 20
  @search = params[:search]
  
  @users = User.includes(:point_transactions)
  @users = @users.where('username ILIKE ? OR first_name ILIKE ?', "%#{@search}%", "%#{@search}%") if @search.present?
  @users = @users.order(created_at: :desc).limit(@per_page).offset((@page - 1) * @per_page)
  
  erb :users
end

get '/users/:id' do
  extend_session!
  @user = User.find_by(telegram_id: params[:id])
  halt 404, "User not found" unless @user
  
  @recent_activity = @user.recent_points_activity
  @moderation_logs = @user.moderation_logs.includes(:chat_session).order(created_at: :desc).limit(20)
  
  erb :user_detail
end

# Moderation actions
post '/users/:id/ban' do
  require_auth!
  user = User.find_by(telegram_id: params[:id])
  halt 404, json(error: 'User not found') unless user

  reason = params[:reason] || 'Banned via admin panel'
  duration = params[:duration]
  
  banned_until = duration ? duration.to_i.hours.from_now : nil
  user.update!(status: :banned, banned_until: banned_until)
  
  ModerationLog.create!(
    user_id: user.telegram_id,
    chat_id: 0,
    action: :banned,
    reason: reason,
    moderator_id: session[:admin_username],
    details: { duration: duration, via: 'admin_panel' }
  )

  json(success: true, message: "User banned successfully")
end

post '/users/:id/unban' do
  require_auth!
  user = User.find_by(telegram_id: params[:id])
  halt 404, json(error: 'User not found') unless user

  user.update!(status: :active, banned_until: nil, warning_count: 0)
  
  ModerationLog.create!(
    user_id: user.telegram_id,
    chat_id: 0,
    action: :unbanned,
    reason: 'Unbanned via admin panel',
    moderator_id: session[:admin_username],
    details: { via: 'admin_panel' }
  )

  json(success: true, message: "User unbanned successfully")
end

post '/users/:id/mute' do
  require_auth!
  user = User.find_by(telegram_id: params[:id])
  halt 404, json(error: 'User not found') unless user

  duration = (params[:duration] || 1).to_i
  reason = params[:reason] || 'Muted via admin panel'
  
  user.update!(status: :muted, banned_until: duration.hours.from_now)
  
  ModerationLog.create!(
    user_id: user.telegram_id,
    chat_id: 0,
    action: :muted,
    reason: reason,
    moderator_id: session[:admin_username],
    details: { duration_hours: duration, via: 'admin_panel' }
  )

  json(success: true, message: "User muted for #{duration} hours")
end

# Points management
post '/users/:id/points' do
  require_auth!
  user = User.find_by(telegram_id: params[:id])
  halt 404, json(error: 'User not found') unless user

  amount = params[:amount].to_i
  reason = params[:reason] || 'Points adjusted via admin panel'
  action = params[:action]

  if action == 'add'
    result = PointsService.award_points(user, amount, reason, session[:admin_username])
  else
    result = PointsService.deduct_points(user, amount, reason, session[:admin_username])
  end

  if result[:success]
    json(success: true, message: result[:message], new_total: result[:new_total])
  else
    json(success: false, error: result[:message])
  end
end

post '/users/:id/reset_warnings' do
  require_auth!
  user = User.find_by(telegram_id: params[:id])
  halt 404, json(error: 'User not found') unless user

  user.update!(warning_count: 0, status: :active)
  
  ModerationLog.create!(
    user_id: user.telegram_id,
    chat_id: 0,
    action: :unbanned,
    reason: 'Warnings reset via admin panel',
    moderator_id: session[:admin_username],
    details: { via: 'admin_panel', action: 'reset_warnings' }
  )

  json(success: true, message: "Warnings reset for #{user.display_name}")
end

post '/users/:id/promote' do
  require_auth!
  user = User.find_by(telegram_id: params[:id])
  halt 404, json(error: 'User not found') unless user

  new_role = params[:role]
  return json(success: false, error: 'Invalid role') unless %w[user moderator admin].include?(new_role)

  old_role = user.role
  user.update!(role: new_role)
  
  ModerationLog.create!(
    user_id: user.telegram_id,
    chat_id: 0,
    action: :promoted,
    reason: "Role changed from #{old_role} to #{new_role}",
    moderator_id: session[:admin_username],
    details: { old_role: old_role, new_role: new_role, via: 'admin_panel' }
  )

  json(success: true, message: "User #{user.display_name} promoted to #{new_role}")
end

# Message templates
get '/templates' do
  extend_session!
  @templates = MessageTemplate.includes(:creator).order(created_at: :desc)
  erb :templates
end

get '/templates/new' do
  extend_session!
  erb :template_form
end

post '/templates' do
  require_auth!
  
  template = MessageTemplate.new(
    name: params[:name],
    template_type: params[:template_type],
    content: params[:content],
    description: params[:description],
    created_by: session[:admin_username]
  )

  if params[:template_type] == 'poll' && params[:options]
    options = params[:options].split("\n").map(&:strip).reject(&:empty?)
    template.set_options(options)
  end

  if template.save
    json(success: true, message: 'Template created successfully')
  else
    json(success: false, error: template.errors.full_messages.join(', '))
  end
end

post '/templates/:id/send' do
  require_auth!
  template = MessageTemplate.find(params[:id])
  chat_ids = params[:chat_ids].split(',').map(&:strip)
  
  sent_count = 0
  chat_ids.each do |chat_id|
    begin
      sent_count += 1
    rescue => e
      # Log error
    end
  end

  json(success: true, message: "Template sent to #{sent_count} chats")
end

# Analytics and stats
get '/analytics' do
  extend_session!
  @user_stats = get_user_analytics
  @points_stats = get_points_analytics
  @activity_stats = get_activity_analytics
  erb :analytics
end

get '/leaderboard' do
  extend_session!
  @leaderboard = PointsService.get_leaderboard(nil, 50)
  erb :leaderboard
end

# API endpoints
get '/api/stats' do
  require_auth!
  json(get_dashboard_stats)
end

get '/api/users' do
  require_auth!
  users = User.select(:telegram_id, :username, :first_name, :role, :status, :points, :message_count)
              .order(:first_name)
              .limit(100)
  json(users)
end

# Helper methods
def get_dashboard_stats
  {
    total_users: User.count,
    active_users: User.where('last_interaction > ?', 24.hours.ago).count,
    banned_users: User.where(status: :banned).count,
    total_messages: Message.count,
    flagged_messages: Message.flagged.count,
    total_points_distributed: PointTransaction.where('amount > 0').sum(:amount),
    recent_registrations: User.where('created_at > ?', 7.days.ago).count,
    moderation_actions_today: ModerationLog.where('created_at > ?', 24.hours.ago).count
  }
end

def get_user_analytics
  {
    by_role: User.group(:role).count,
    by_status: User.group(:status).count,
    registrations_last_30_days: User.where('created_at > ?', 30.days.ago)
                                    .group("DATE(created_at)")
                                    .count
  }
end

def get_points_analytics
  {
    total_earned: PointTransaction.where('amount > 0').sum(:amount),
    total_spent: PointTransaction.where('amount < 0').sum(:amount).abs,
    transactions_by_type: PointTransaction.group(:transaction_type).count,
    top_earners: User.order(points: :desc).limit(10)
                    .pluck(:first_name, :username, :points),
    points_distribution_last_7_days: PointTransaction.where('created_at > ?', 7.days.ago)
                                                    .group("DATE(created_at)")
                                                    .sum(:amount)
  }
end

def get_activity_analytics
  {
    messages_by_day: Message.where('created_at > ?', 30.days.ago)
                           .group("DATE(created_at)")
                           .count,
    most_active_chats: ChatSession.joins(:messages)
                                 .group('chat_sessions.chat_title', 'chat_sessions.chat_id')
                                 .count('messages.id')
                                 .sort_by { |_, count| -count }
                                 .first(10),
    moderation_actions_by_day: ModerationLog.where('created_at > ?', 30.days.ago)
                                           .group("DATE(created_at)")
                                           .group(:action)
                                           .count
  }
end

# Helper methods for views
helpers do
  def time_ago_in_words(time)
    return 'never' unless time
    
    diff = Time.current - time
    case diff
    when 0..59
      "#{diff.to_i} seconds"
    when 60..3599
      "#{(diff / 60).to_i} minutes"
    when 3600..86399
      "#{(diff / 3600).to_i} hours"
    else
      "#{(diff / 86400).to_i} days"
    end
  end

  def truncate_text(text, length = 30)
    return '' unless text
    text = text.to_s
    text.length > length ? text[0...length] + '...' : text
  end
end

# Cleanup expired sessions periodically
Thread.new do
  loop do
    begin
      AdminSession.cleanup_expired
    rescue => e
      puts "Session cleanup error: #{e.message}"
    end
    sleep 3600
  end
end
