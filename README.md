Advanced Telegram Bot with Claude Integration
A production-ready Telegram bot featuring Claude 4 integration, advanced content moderation, user management, and anti-violence systems.
🚀 Features
Core Functionality
Claude 4 Integration: Latest Sonnet 4 model with context-aware responses
Smart Conversations: Tag the bot to chat with Claude AI
Multi-language Support: Automatic language detection and responses
Security & Moderation
Violence Detection: Automatic analysis and prevention of violent content
Toxicity Filtering: Real-time toxicity scoring and moderation
Content Analysis: Claude-powered deep content understanding
Rate Limiting: Prevents spam and abuse
Auto-Moderation: Automatic warnings, mutes, and bans
User Management
Role System: User/Moderator/Admin hierarchies
User Tracking: Message counts, activity monitoring
Ban System: Temporary and permanent bans with auto-expiry
Warning System: Progressive punishment system
Admin Tools
Moderation Commands: Ban, mute, warn, promote users
Analytics Dashboard: User and chat statistics
Chat Management: Enable/disable moderation per chat
Audit Logging: Complete moderation action history
📋 Requirements
Ruby 2.7+
SQLite3 (or PostgreSQL)
Redis (optional, for rate limiting)
Telegram Bot Token
Anthropic API Key
🛠️ Installation
Clone and setup:
bash
git clone <your-repo>
cd telegram-claude-bot
gem install bundler
bundle install
Run setup script:
bash
ruby setup.rb
Configure environment: Edit .env file with your tokens:
env
BILLY_TELEGRAM_TOKEN=your_bot_token
BILLY_BOT_NAME=your_bot_username  
ANTHROPIC_API_KEY=your_anthropic_key
Start the bot:
bash
ruby main.rb
🎮 Usage
Basic Commands
@yourbot <message> - Chat with Claude
/start - Initialize bot and see welcome message
/help - Show available commands
/status - Check your account status
Moderation Commands (Moderator+)
/ban @user [reason] - Ban user permanently
/unban @user - Remove ban and clear warnings
/mute @user [hours] [reason] - Temporarily mute user
/warn @user [reason] - Issue warning (3 warnings = auto-ban)
/stats [@user] - Show user or chat statistics
/moderation [on|off|settings] - Control moderation settings
Admin Commands (Admin only)
/promote @user [moderator|admin] - Promote user role
/demote @user - Demote user to regular user
/cleanup - Clean up expired bans and restrictions
🛡️ Security Features
Content Moderation
Keyword Detection: Instant flagging of violent/toxic terms
Claude Analysis: Deep contextual content analysis
Scoring System: Violence and toxicity scores (0.0-1.0)
Configurable Thresholds: Adjust sensitivity via environment variables
User Protection
Progressive Punishment: Warning → Mute → Temporary Ban → Permanent Ban
Appeal System: Admins can review and reverse actions
Role Protection: Admins and moderators cannot be auto-moderated
Audit Trail: Complete logging of all moderation actions
Rate Limiting
Per-User Limits: Configurable message limits per minute/hour
Chat-Specific: Different limits for private vs group chats
Redis Backend: Distributed rate limiting support
Graceful Degradation: Works without Redis
📊 Analytics
User Metrics
Message count and activity patterns
Warning and violation history
Role and status tracking
Interaction timestamps
Chat Metrics
Total messages and flagged content
Active user counts
Moderation effectiveness
Settings and configuration
System Metrics
Claude API usage and costs
Response times and errors
Rate limiting effectiveness
Database performance
⚙️ Configuration
Environment Variables
env
# Required
BILLY_TELEGRAM_TOKEN=your_bot_token
BILLY_BOT_NAME=your_bot_username
ANTHROPIC_API_KEY=your_anthropic_key

# Optional
DATABASE_URL=sqlite3://db/bot.sqlite3
REDIS_URL=redis://localhost:6379
LOG_LEVEL=INFO

# Moderation Settings
ENABLE_AUTO_MODERATION=true
VIOLENCE_THRESHOLD=0.7
TOXICITY_THRESHOLD=0.8
MAX_MESSAGES_PER_MINUTE=10
MAX_MESSAGES_PER_HOUR=100
MAX_CLAUDE_TOKENS=1000
Chat-Specific Settings
Each chat can have individual settings:
Moderation enabled/disabled
Auto-delete flagged messages
Custom thresholds
Welcome messages
🏗️ Architecture
Database Schema
Users: Telegram user data, roles, status
ChatSessions: Chat configuration and settings
Messages: Content, analysis results, responses
ModerationLogs: Audit trail of all actions
Service Layer
ClaudeService: Claude API integration and response generation
ModerationService: Content analysis and automatic actions
UserService: User and chat management
RateLimiter: Spam protection and rate limiting
Handler System
AdminHandler: Administrative command processing
MessageHandler: Content processing and routing
ErrorHandler: Graceful error handling and recovery
🚀 Deployment
Docker Deployment
dockerfile
FROM ruby:3.0-alpine
WORKDIR /app
COPY Gemfile* ./
RUN bundle install
COPY . .
CMD ["ruby", "main.rb"]
Production Checklist
 Set up monitoring (logs, metrics)
 Configure log rotation
 Set up database backups
 Configure Redis persistence
 Set up health checks
 Configure rate limiting
 Review security settings
 Test disaster recovery
Scaling Considerations
Use PostgreSQL for production
Redis cluster for high availability
Load balancer for multiple bot instances
Separate worker processes for heavy tasks
Claude API rate limiting and costs
🔧 Development
Adding New Features
Create service classes in lib/services/
Add handlers in lib/handlers/
Update database schema as needed
Add configuration variables
Update documentation
Testing
bash
# Run linter
bundle exec rubocop

# Database migrations
ruby -r './config/database.rb' -e "puts 'DB connected'"

# Manual testing
ruby -r './lib/models.rb' -e "puts User.count"
Debugging
Check logs for errors and performance
Monitor Claude API usage and costs
Review moderation effectiveness
Track user behavior patterns
📝 License
This project is licensed under the MIT License - see the LICENSE file for details.
🤝 Contributing
Fork the repository
Create a feature branch
Make your changes
Add tests if applicable
Submit a pull request
📞 Support
Check logs first: tail -f bot.log
Review configuration: .env file
Test Claude API: Check API key and limits
Database issues: Check SQLite file permissions
Rate limiting: Check Redis connection
🎯 Roadmap
Version 2.0
 Web dashboard for administration
 Advanced analytics and reporting
 Multi-language interface
 Custom moderation rules
 Integration with external APIs
 Mobile app for management
Future Features
 Machine learning for better content detection
 Voice message support
 File and image analysis
 Scheduled messages and tasks
 Integration with other chat platforms
 Advanced user reputation system
Built with ❤️ using Ruby, Claude 4, and Telegram Bot API
