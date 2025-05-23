# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
```bash
rake test          # Run tests with database setup
rake spec          # Run RSpec tests only  
rake               # Default task runs full test suite
```

### Database
```bash
rake db:migrate     # Run migrations
rake db:reset_test  # Reset test database
```

### Running the Application
```bash
./run.sh           # Production Docker deployment (validates env, builds, starts services)
ruby main.rb       # Run bot directly (development)
ruby web_app.rb    # Run web admin interface only
```

### Docker Operations
```bash
docker-compose up -d                    # Start all services
docker-compose logs -f telegram-bot     # View bot logs  
docker-compose logs -f web-admin        # View web admin logs
docker-compose exec telegram-bot sh     # Shell into bot container
docker-compose down                     # Stop all services
```

## Architecture Overview

### Service-Oriented Design
The bot uses a layered service architecture with clear separation of concerns:

- **Services** (`lib/services/`) - Core business logic encapsulated in service objects
- **Handlers** (`lib/handlers/`) - Feature-specific command and interaction handlers  
- **Middleware** (`lib/middleware/`) - Cross-cutting concerns like rate limiting
- **Models** (`lib/models.rb`) - ActiveRecord models with business logic and associations

### Key Architectural Patterns

**Message Processing Pipeline**: `MessageHandler` routes incoming messages to appropriate handlers based on content type (commands, mentions, etc.)

**Service Objects**: Complex operations are encapsulated in service classes with clear interfaces (e.g., `PointsService.award_points`, `ModerationService.analyze_content`)

**Role-Based Authorization**: Three-tier system (user/moderator/admin) with different permissions enforced in handlers

**Event-Driven Moderation**: Messages flow through violence/toxicity detection, with automatic actions based on configurable thresholds

### Core Components

**BotManager**: Main orchestrator that initializes services and starts the Telegram bot polling

**ClaudeInteractionHandler**: Manages AI conversations with context preservation and error handling

**Web Admin Interface**: Sinatra-based dashboard for user management, analytics, and system administration

### Database Schema
The application uses ActiveRecord with these primary models:
- `User` - Telegram users with roles, status, points, and moderation history
- `ChatSession` - Chat-specific configuration and moderation settings
- `Message` - Content analysis, responses, and flagging
- `PointTransaction` - Points system with full audit trail
- `ModerationLog` - Complete audit trail of all moderation actions

### Testing Strategy
- **RSpec** with factory-based test data generation
- **Custom matchers** for ActiveRecord associations and enums
- **Comprehensive coverage** of models, services, handlers, and middleware
- **Transaction-based cleanup** for fast, isolated tests

### Environment Configuration
The bot requires these essential environment variables:
- `BILLY_TELEGRAM_TOKEN` - Telegram bot token
- `ANTHROPIC_API_KEY` - Claude API access
- `BILLY_BOT_NAME` - Bot username for mentions

Web admin credentials default to admin/admin123 but should be configured via `ADMIN_USERNAME` and `ADMIN_PASSWORD`.
