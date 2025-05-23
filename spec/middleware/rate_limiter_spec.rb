require 'spec_helper'

RSpec.describe RateLimiter do
  let(:rate_limiter) { RateLimiter.new }
  let(:user_id) { 12345 }
  let(:chat_id) { -67890 }

  before do
    # Mock Redis to avoid external dependencies in tests
    @redis_mock = double('Redis')
    allow(Redis).to receive(:new).and_return(@redis_mock)
    allow(@redis_mock).to receive(:incr)
    allow(@redis_mock).to receive(:expire)
    allow(@redis_mock).to receive(:get)
    allow(@redis_mock).to receive(:keys)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('REDIS_URL').and_return('redis://localhost:6379')
    allow(@redis_mock).to receive(:del)
  end

  describe '#initialize' do
    context 'when Redis is available' do
      it 'initializes with Redis connection' do
        expect(rate_limiter.instance_variable_get(:@redis)).to eq(@redis_mock)
      end
    end

    context 'when Redis is not available' do
      before do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)
        allow(STDOUT).to receive(:puts) # Suppress warning message
      end

      it 'initializes with nil Redis and shows warning' do
        limiter = RateLimiter.new
        expect(limiter.instance_variable_get(:@redis)).to be_nil
        expect(STDOUT).to have_received(:puts).with(/Warning: Redis not available/)
      end
    end
  end

  describe '#check_rate_limit' do
    let(:current_time) { Time.now.to_i }
    let(:minute_key) { "rate_limit:#{user_id}:#{chat_id}:#{current_time / 60}" }
    let(:hour_key) { "rate_limit:#{user_id}:#{chat_id}:#{current_time / 3600}" }

    before do
      allow(Time).to receive(:now).and_return(Time.at(current_time))
    end

    context 'when Redis is available' do
      context 'within rate limits' do
        before do
          allow(@redis_mock).to receive(:incr).with(minute_key).and_return(5)
          allow(@redis_mock).to receive(:incr).with(hour_key).and_return(50)
        end

        it 'returns true and sets expiry on first increment' do
          allow(@redis_mock).to receive(:incr).with(minute_key).and_return(1)
          allow(@redis_mock).to receive(:incr).with(hour_key).and_return(1)

          result = rate_limiter.check_rate_limit(user_id, chat_id)
          
          expect(result).to be true
          expect(@redis_mock).to have_received(:expire).with(minute_key, 60)
          expect(@redis_mock).to have_received(:expire).with(hour_key, 3600)
        end

        it 'returns true when within limits' do
          result = rate_limiter.check_rate_limit(user_id, chat_id)
          expect(result).to be true
        end
      end

      context 'exceeding minute limit' do
        before do
          allow(@redis_mock).to receive(:incr).with(minute_key).and_return(11)
          allow(ENV).to receive(:[]).with('MAX_MESSAGES_PER_MINUTE').and_return('10')
        end

        it 'returns false' do
          result = rate_limiter.check_rate_limit(user_id, chat_id)
          expect(result).to be false
        end
      end

      context 'exceeding hour limit' do
        before do
          allow(@redis_mock).to receive(:incr).with(minute_key).and_return(5)
          allow(@redis_mock).to receive(:incr).with(hour_key).and_return(101)
          allow(ENV).to receive(:[]).with('MAX_MESSAGES_PER_HOUR').and_return('100')
        end

        it 'returns false' do
          result = rate_limiter.check_rate_limit(user_id, chat_id)
          expect(result).to be false
        end
      end

      context 'with custom environment limits' do
        before do
          allow(ENV).to receive(:[]).with('MAX_MESSAGES_PER_MINUTE').and_return('5')
          allow(ENV).to receive(:[]).with('MAX_MESSAGES_PER_HOUR').and_return('50')
          allow(@redis_mock).to receive(:incr).with(minute_key).and_return(6)
        end

        it 'uses custom limits' do
          result = rate_limiter.check_rate_limit(user_id, chat_id)
          expect(result).to be false
        end
      end

      context 'when Redis raises an error' do
        before do
          allow(@redis_mock).to receive(:incr).and_raise(Redis::BaseError.new('Connection lost'))
          allow(STDOUT).to receive(:puts) # Suppress error message
        end

        it 'returns true and logs error' do
          result = rate_limiter.check_rate_limit(user_id, chat_id)
          expect(result).to be true
          expect(STDOUT).to have_received(:puts).with(/Redis error in rate limiter/)
        end
      end
    end

    context 'when Redis is not available' do
      let(:rate_limiter) do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)
        allow(STDOUT).to receive(:puts)
        RateLimiter.new
      end

      it 'returns true' do
        result = rate_limiter.check_rate_limit(user_id, chat_id)
        expect(result).to be true
      end
    end
  end

  describe '#get_remaining_limit' do
    let(:current_time) { Time.now.to_i }
    let(:minute_key) { "rate_limit:#{user_id}:#{chat_id}:#{current_time / 60}" }
    let(:hour_key) { "rate_limit:#{user_id}:#{chat_id}:#{current_time / 3600}" }

    before do
      allow(Time).to receive(:now).and_return(Time.at(current_time))
    end

    context 'when Redis is available' do
      before do
        allow(@redis_mock).to receive(:get).with(minute_key).and_return('3')
        allow(@redis_mock).to receive(:get).with(hour_key).and_return('25')
      end

      it 'returns remaining limits' do
        result = rate_limiter.get_remaining_limit(user_id, chat_id)
        
        expect(result[:minute]).to eq(7) # 10 - 3
        expect(result[:hour]).to eq(75)  # 100 - 25
      end

      it 'returns 0 when limit exceeded' do
        allow(@redis_mock).to receive(:get).with(minute_key).and_return('15')
        
        result = rate_limiter.get_remaining_limit(user_id, chat_id)
        expect(result[:minute]).to eq(0)
      end

      context 'when Redis raises an error' do
        before do
          allow(@redis_mock).to receive(:get).and_raise(Redis::BaseError.new('Connection lost'))
        end

        it 'returns unlimited values' do
          result = rate_limiter.get_remaining_limit(user_id, chat_id)
          expect(result[:minute]).to eq(999)
          expect(result[:hour]).to eq(999)
        end
      end
    end

    context 'when Redis is not available' do
      let(:rate_limiter) do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)
        allow(STDOUT).to receive(:puts)
        RateLimiter.new
      end

      it 'returns unlimited values' do
        result = rate_limiter.get_remaining_limit(user_id, chat_id)
        expect(result[:minute]).to eq(999)
        expect(result[:hour]).to eq(999)
      end
    end
  end

  describe '#reset_user_limits' do
    let(:pattern) { "rate_limit:#{user_id}:*" }
    let(:keys) { ["rate_limit:#{user_id}:#{chat_id}:123", "rate_limit:#{user_id}:#{chat_id}:124"] }

    context 'when Redis is available' do
      before do
        allow(@redis_mock).to receive(:keys).with(pattern).and_return(keys)
      end

      it 'deletes all user rate limit keys' do
        rate_limiter.reset_user_limits(user_id)
        
        expect(@redis_mock).to have_received(:keys).with(pattern)
        expect(@redis_mock).to have_received(:del).with(*keys)
      end

      context 'when no keys found' do
        before do
          allow(@redis_mock).to receive(:keys).with(pattern).and_return([])
        end

        it 'does not attempt to delete' do
          rate_limiter.reset_user_limits(user_id)
          
          expect(@redis_mock).to have_received(:keys).with(pattern)
          expect(@redis_mock).not_to have_received(:del)
        end
      end

      context 'when Redis raises an error' do
        before do
          allow(@redis_mock).to receive(:keys).and_raise(Redis::BaseError.new('Connection lost'))
          allow(STDOUT).to receive(:puts) # Suppress error message
        end

        it 'handles error gracefully' do
          rate_limiter.reset_user_limits(user_id)
          expect(STDOUT).to have_received(:puts).with(/Redis error resetting limits/)
        end
      end
    end

    context 'when Redis is not available' do
      let(:rate_limiter) do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)
        allow(STDOUT).to receive(:puts)
        RateLimiter.new
      end

      it 'does nothing' do
        expect { rate_limiter.reset_user_limits(user_id) }.not_to raise_error
      end
    end
  end
end