FROM ruby:3.2-alpine

# Install dependencies
RUN apk add --no-cache \
    build-base \
    sqlite-dev \
    tzdata \
    curl

# Set working directory
WORKDIR /app

# Copy Gemfile first for better caching
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle install

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p db logs

# Set permissions
RUN chmod +x setup.rb main.rb

# Create non-root user
RUN addgroup -g 1000 botuser && \
    adduser -D -s /bin/sh -u 1000 -G botuser botuser && \
    chown -R botuser:botuser /app

USER botuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD pgrep -f "ruby main.rb" || exit 1

# Expose port (if needed for future web interface)
EXPOSE 3000

# Default command
CMD ["ruby", "main.rb"]
