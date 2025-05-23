require 'spec_helper'

RSpec.describe UserService do
  describe '.find_or_create_user' do
    let(:telegram_user) do
      double('TelegramUser',
        id: 12345,
        username: 'testuser',
        first_name: 'John',
        last_name: 'Doe',
        language_code: 'en'
      )
    end

    context 'when user does not exist' do
      it 'creates new user with telegram user data' do
        expect {
          user = UserService.find_or_create_user(telegram_user)
          expect(user.telegram_id).to eq(12345)
          expect(user.username).to eq('testuser')
          expect(user.first_name).to eq('John')
          expect(user.last_name).to eq('Doe')
          expect(user.language_code).to eq('en')
          expect(user.last_interaction).to be_within(1.second).of(Time.current)
        }.to change { User.count }.by(1)
      end

      it 'uses default language when not provided' do
        allow(telegram_user).to receive(:language_code).and_return(nil)
        user = UserService.find_or_create_user(telegram_user)
        expect(user.language_code).to eq('en')
      end
    end

    context 'when user exists' do
      let!(:existing_user) { create(:user, telegram_id: 12345, username: 'oldusername') }

      it 'updates existing user data' do
        expect {
          user = UserService.find_or_create_user(telegram_user)
          expect(user.id).to eq(existing_user.id)
          expect(user.username).to eq('testuser')
          expect(user.last_interaction).to be_within(1.second).of(Time.current)
        }.not_to change { User.count }
      end
    end
  end

  describe '.find_or_create_chat' do
    let(:telegram_chat) do
      double('TelegramChat',
        id: -67890,
        type: 'supergroup',
        title: 'Test Group'
      )
    end

    context 'when chat does not exist' do
      it 'creates new chat with telegram chat data' do
        expect {
          chat = UserService.find_or_create_chat(telegram_chat)
          expect(chat.chat_id).to eq(-67890)
          expect(chat.chat_type).to eq('supergroup')
          expect(chat.chat_title).to eq('Test Group')
          expect(chat.moderation_enabled).to be true
        }.to change { ChatSession.count }.by(1)
      end

      it 'disables moderation for private chats' do
        allow(telegram_chat).to receive(:type).and_return('private')
        chat = UserService.find_or_create_chat(telegram_chat)
        expect(chat.moderation_enabled).to be false
      end
    end

    context 'when chat exists' do
      let!(:existing_chat) { create(:chat_session, chat_id: -67890, chat_title: 'Old Title') }

      it 'updates existing chat data' do
        expect {
          chat = UserService.find_or_create_chat(telegram_chat)
          expect(chat.id).to eq(existing_chat.id)
          expect(chat.chat_title).to eq('Test Group')
        }.not_to change { ChatSession.count }
      end
    end
  end

  describe '.can_user_message?' do
    let(:chat_session) { create(:chat_session) }

    context 'when user is banned permanently' do
      let(:user) { create(:user, status: :banned, banned_until: nil) }

      it 'returns false' do
        expect(UserService.can_user_message?(user, chat_session)).to be false
      end
    end

    context 'when user is banned with future expiry' do
      let(:user) { create(:user, status: :banned, banned_until: 1.hour.from_now) }

      it 'returns false' do
        expect(UserService.can_user_message?(user, chat_session)).to be false
      end
    end

    context 'when user is muted with future expiry' do
      let(:user) { create(:user, status: :muted, banned_until: 1.hour.from_now) }

      it 'returns false' do
        expect(UserService.can_user_message?(user, chat_session)).to be false
      end
    end

    context 'when user ban/mute has expired' do
      let(:user) { create(:user, status: :muted, banned_until: 1.hour.ago) }

      it 'resets status and returns true' do
        result = UserService.can_user_message?(user, chat_session)
        expect(result).to be true
        expect(user.reload.status).to eq('active')
        expect(user.banned_until).to be_nil
      end
    end

    context 'when user is active' do
      let(:user) { create(:user, status: :active) }

      it 'returns true' do
        expect(UserService.can_user_message?(user, chat_session)).to be true
      end
    end
  end

  describe '.promote_user' do
    let(:user) { create(:user, role: :user) }
    let(:admin) { create(:user, :admin) }

    context 'when user exists' do
      it 'promotes user and logs action' do
        result = UserService.promote_user(user.telegram_id, :moderator, admin.telegram_id)
        
        expect(result[:success]).to be true
        expect(result[:message]).to include('promoted to moderator')
        expect(user.reload.role).to eq('moderator')
        
        log = ModerationLog.last
        expect(log.action).to eq('promoted')
        expect(log.user_id).to eq(user.telegram_id)
        expect(log.moderator_id).to eq(admin.telegram_id)
      end
    end

    context 'when user does not exist' do
      it 'returns error' do
        result = UserService.promote_user(99999, :moderator, admin.telegram_id)
        expect(result[:success]).to be false
        expect(result[:message]).to eq('User not found')
      end
    end
  end

  describe '.get_user_stats' do
    let(:user) { create(:user) }

    before do
      create(:message, user: user, created_at: 12.hours.ago)
      create(:message, user: user, flagged: true, created_at: 1.day.ago)
    end

    context 'when user exists' do
      it 'returns comprehensive user statistics' do
        stats = UserService.get_user_stats(user.telegram_id)
        
        expect(stats[:username]).to eq(user.username)
        expect(stats[:role]).to eq(user.role)
        expect(stats[:status]).to eq(user.status)
        expect(stats[:recent_messages]).to eq(1)
        expect(stats[:flagged_messages]).to eq(1)
        expect(stats[:member_since]).to eq(user.created_at)
      end
    end

    context 'when user does not exist' do
      it 'returns nil' do
        stats = UserService.get_user_stats(99999)
        expect(stats).to be_nil
      end
    end
  end

  describe '.get_chat_stats' do
    let(:chat_session) { create(:chat_session) }
    let(:user) { create(:user) }

    before do
      create(:message, chat_session: chat_session, user: user, created_at: 12.hours.ago)
      create(:message, chat_session: chat_session, user: user, flagged: true, created_at: 1.day.ago)
    end

    context 'when chat exists' do
      it 'returns comprehensive chat statistics' do
        stats = UserService.get_chat_stats(chat_session.chat_id)
        
        expect(stats[:chat_title]).to eq(chat_session.chat_title)
        expect(stats[:chat_type]).to eq(chat_session.chat_type)
        expect(stats[:moderation_enabled]).to eq(chat_session.moderation_enabled)
        expect(stats[:total_messages]).to eq(2)
        expect(stats[:flagged_messages]).to eq(1)
        expect(stats[:active_users]).to eq(1)
      end
    end

    context 'when chat does not exist' do
      it 'returns nil' do
        stats = UserService.get_chat_stats(-99999)
        expect(stats).to be_nil
      end
    end
  end

  describe '.cleanup_expired_bans' do
    let!(:expired_user1) { create(:user, status: :muted, banned_until: 1.hour.ago) }
    let!(:expired_user2) { create(:user, status: :banned, banned_until: 1.day.ago) }
    let!(:active_banned_user) { create(:user, status: :banned, banned_until: 1.hour.from_now) }
    let!(:permanent_banned_user) { create(:user, status: :banned, banned_until: nil) }

    it 'resets status for expired bans only' do
      count = UserService.cleanup_expired_bans
      
      expect(count).to eq(2)
      expect(expired_user1.reload.status).to eq('active')
      expect(expired_user1.banned_until).to be_nil
      expect(expired_user2.reload.status).to eq('active')
      expect(expired_user2.banned_until).to be_nil
      expect(active_banned_user.reload.status).to eq('banned')
      expect(permanent_banned_user.reload.status).to eq('banned')
    end
  end
end
