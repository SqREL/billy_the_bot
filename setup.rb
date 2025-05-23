#!/usr/bin/env ruby

puts "🚀 Setting up Telegram Claude Bot..."

# Check Ruby version
required_version = '2.7.0'
if RUBY_VERSION < required_version
  puts "❌ Ruby #{required_version} or higher required. Current: #{RUBY_VERSION}"
  exit 1
end

# Create directories
%w[db lib lib/services lib/models lib/handlers lib/middleware config].each do |dir|
  Dir.mkdir(dir) unless Dir.exist?(dir)
  puts "✅ Created directory: #{dir}"
end

# Copy .env.example to .env if it doesn't exist
unless File.exist?('.env')
  if File.exist?('.env.example')
    require 'fileutils'
    FileUtils.cp('.env.example', '.env')
    puts "✅ Created .env file from .env.example"
    puts "⚠️  Please edit .env file with your actual tokens and keys"
  else
    puts "⚠️  Please create .env file with your configuration"
  end
end

# Install gems
puts "\n📦 Installing gems..."
system('bundle install')

# Setup database
puts "\n🗄️  Setting up database..."
require_relative 'config/database'

puts "✅ Database setup complete"

# Create first admin user (optional)
puts "\n👑 Setup first admin user? (y/n)"
response = gets.chomp.downcase

if response == 'y'
  print "Enter Telegram user ID for first admin: "
  admin_id = gets.chomp.to_i
  
  if admin_id > 0
    require_relative 'lib/models'
    
    admin_user = User.find_or_initialize_by(telegram_id: admin_id)
    admin_user.update!(
      role: :admin,
      first_name: "Admin",
      username: "admin_#{admin_id}"
    )
    puts "✅ Admin user created with ID: #{admin_id}"
  else
    puts "❌ Invalid user ID"
  end
end

puts <<~SETUP_COMPLETE

🎉 Setup Complete!

Next steps:
1. Edit your .env file with real tokens:
   - BILLY_TELEGRAM_TOKEN (get from @BotFather)
   - ANTHROPIC_API_KEY (get from Anthropic Console)
   - BILLY_BOT_NAME (your bot's username)

2. Install Redis (optional, for rate limiting):
   - macOS: brew install redis
   - Ubuntu: sudo apt install redis-server
   - Start: redis-server

3. Run the bot:
   ruby main.rb

4. Test in Telegram:
   - /start - Initialize bot
   - @yourbot hello - Chat with Claude
   - /help - See all commands

🛡️ Security Features Enabled:
- Content moderation with Claude analysis
- User role management (user/moderator/admin)
- Rate limiting and spam protection
- Violence and toxicity detection
- Automatic user warnings and bans

📊 Admin Commands Available:
- /ban, /unban, /mute, /warn users
- /promote, /demote user roles  
- /stats for user and chat analytics
- /moderation to control settings

Happy botting! 🤖

SETUP_COMPLETE
