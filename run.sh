#!/bin/bash

set -e

echo "🚀 Starting Telegram Claude Bot with Web Admin UI..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Check if .env file exists
if [ ! -f .env ]; then
    if [ -f .env.production ]; then
        echo "📝 Copying .env.production to .env"
        cp .env.production .env
        echo "⚠️  Please edit .env file with your actual tokens before continuing!"
        echo "Press any key to continue after editing .env..."
        read -n 1
    else
        echo "❌ No .env file found. Please create one with your configuration."
        exit 1
    fi
fi

# Source environment variables
source .env

# Validate required environment variables
if [ -z "$BILLY_TELEGRAM_TOKEN" ] || [ "$BILLY_TELEGRAM_TOKEN" = "your_bot_token_here" ]; then
    echo "❌ Please set BILLY_TELEGRAM_TOKEN in .env file"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ] || [ "$ANTHROPIC_API_KEY" = "your_anthropic_api_key_here" ]; then
    echo "❌ Please set ANTHROPIC_API_KEY in .env file"
    exit 1
fi

if [ -z "$BILLY_BOT_NAME" ] || [ "$BILLY_BOT_NAME" = "your_bot_username" ]; then
    echo "❌ Please set BILLY_BOT_NAME in .env file"
    exit 1
fi

echo "✅ Environment variables validated"

# Build and start containers
echo "🔨 Building Docker containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Check if containers are running
if docker-compose ps | grep -q "Up"; then
    echo "✅ Bot and Web UI are running successfully!"
    echo ""
    echo "📊 Container Status:"
    docker-compose ps
    echo ""
    echo "🌐 Web Admin Panel:"
    echo "  URL: http://localhost:3000"
    echo "  Username: ${ADMIN_USERNAME:-admin}"
    echo "  Password: ${ADMIN_PASSWORD:-admin123}"
    echo ""
    echo "📋 Useful Commands:"
    echo "  View bot logs:     docker-compose logs -f telegram-bot"
    echo "  View web logs:     docker-compose logs -f web-admin"
    echo "  Stop everything:   docker-compose down"
    echo "  Restart bot:       docker-compose restart telegram-bot"
    echo "  Restart web:       docker-compose restart web-admin"
    echo "  Enter bot shell:   docker-compose exec telegram-bot sh"
    echo "  View Redis:        docker-compose exec redis redis-cli"
    echo ""
    echo "🤖 Your bot should now be available in Telegram!"
    echo "Test with: /start or @${BILLY_BOT_NAME} hello"
    echo ""
    echo "💰 Points System Features:"
    echo "  • /points - Check your points"
    echo "  • /daily - Claim daily bonus"
    echo "  • /leaderboard - See top users"
    echo "  • /give @user points reason - Give points (admin)"
    echo ""
    echo "🛡️ Admin Features:"
    echo "  • Ban/mute/warn users via web UI or commands"
    echo "  • Bulk points distribution"
    echo "  • Message templates and broadcasting"
    echo "  • Real-time analytics and monitoring"
    echo "  • Violence/toxicity detection and auto-moderation"
else
    echo "❌ Failed to start containers"
    echo "📋 Checking logs..."
    docker-compose logs
    exit 1
fi

# Optional: Show first-time setup instructions
echo ""
echo "🎯 First Time Setup:"
echo "1. Go to http://localhost:3000 and login to admin panel"
echo "2. Create your first admin user via web UI or bot command"
echo "3. Configure moderation settings in web panel"
echo "4. Test the bot with /start command in Telegram"
echo "5. Try giving yourself points: /give @yourusername 100 Welcome bonus"
echo ""
echo "Happy botting! 🤖✨"
