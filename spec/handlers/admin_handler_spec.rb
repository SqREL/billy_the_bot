require 'spec_helper'

RSpec.describe AdminHandler do
  let(:bot) { double('Bot', api: double('API')) }
  let(:user_service) { double('UserService') }
  let(:handler) { AdminHandler.new(bot, user_service) }
  let(:admin) { create(:user, :admin) }
  let(:moderator) { create(:user, :moderator) }
  let(:regular_user) { create(:user) }
  let(:chat_session) { create(:chat_session) }
  let(:message) { double('Message', chat: double('Chat', id: chat_session.chat_id), message_id: 123) }

  before do
    allow(bot.api).to receive(:send_message)
  end

  describe '#handle_admin_command' do
    context 'when user is not admin or moderator' do
      it 'returns false' do
        result = handler.handle_admin_command(message, regular_user, chat_session, '/ban', ['@target'])
        expect(result).to be false
      end
    end

    context 'when user is admin' do
      it 'processes valid admin commands' do
        allow(handler).to receive(:handle_ban_command).and_return(true)
        result = handler.handle_admin_command(message, admin, chat_session, '/ban', ['@target'])
        expect(result).to be true
      end
    end

    context 'when command is not recognized' do
      it 'returns false' do
        result = handler.handle_admin_command(message, admin, chat_session, '/unknown', [])
        expect(result).to be false
      end
    end
  end

  describe '#handle_ban_command' do
    let!(:target_user) { create(:user, username: 'target') }

    context 'with valid arguments' do
      it 'bans user and creates moderation log' do
        result = handler.send(:handle_ban_command, message, admin, ['@target', 'spam'])
        
        expect(result).to be true
        expect(target_user.reload.status).to eq('banned')
        expect(target_user.banned_until).to be_nil
        
        log = ModerationLog.last
        expect(log.action).to eq('banned')
        expect(log.user_id).to eq(target_user.telegram_id)
        expect(log.moderator_id).to eq(admin.telegram_id)
        expect(log.reason).to eq('spam')
        
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: include('banned'),
          reply_to_message_id: 123
        )
      end

      it 'prevents banning admins' do
        admin_target = create(:user, :admin, username: 'admin_target')
        result = handler.send(:handle_ban_command, message, admin, ['@admin_target'])
        
        expect(result).to be true
        expect(admin_target.reload.status).to eq('active')
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: '❌ Cannot ban admins',
          reply_to_message_id: 123
        )
      end
    end

    context 'with invalid arguments' do
      it 'returns error for empty arguments' do
        result = handler.send(:handle_ban_command, message, admin, [])
        expect(result).to be true
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: '❌ Usage: /ban @username [reason]',
          reply_to_message_id: 123
        )
      end

      it 'returns error for non-existent user' do
        result = handler.send(:handle_ban_command, message, admin, ['@nonexistent'])
        expect(result).to be true
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: '❌ User not found',
          reply_to_message_id: 123
        )
      end
    end
  end

  describe '#handle_unban_command' do
    let!(:banned_user) { create(:user, username: 'banned', status: :banned, warning_count: 3) }

    it 'unbans user and resets warnings' do
      result = handler.send(:handle_unban_command, message, admin, ['@banned'])
      
      expect(result).to be true
      expect(banned_user.reload.status).to eq('active')
      expect(banned_user.banned_until).to be_nil
      expect(banned_user.warning_count).to eq(0)
      
      log = ModerationLog.last
      expect(log.action).to eq('unbanned')
    end
  end

  describe '#handle_mute_command' do
    let!(:target_user) { create(:user, username: 'target') }

    it 'mutes user for specified duration' do
      result = handler.send(:handle_mute_command, message, admin, ['@target', '2', 'disruption'])
      
      expect(result).to be true
      expect(target_user.reload.status).to eq('muted')
      expect(target_user.banned_until).to be_within(1.minute).of(2.hours.from_now)
      
      log = ModerationLog.last
      expect(log.action).to eq('muted')
      expect(log.details['duration_hours']).to eq(2)
    end

    it 'uses default duration of 1 hour' do
      result = handler.send(:handle_mute_command, message, admin, ['@target'])
      
      expect(result).to be true
      expect(target_user.reload.banned_until).to be_within(1.minute).of(1.hour.from_now)
    end
  end

  describe '#handle_warn_command' do
    let!(:target_user) { create(:user, username: 'target', warning_count: 0) }

    it 'warns user and increments warning count' do
      result = handler.send(:handle_warn_command, message, admin, ['@target', 'inappropriate'])
      
      expect(result).to be true
      expect(target_user.reload.warning_count).to eq(1)
      expect(target_user.status).to eq('warned')
      
      log = ModerationLog.last
      expect(log.action).to eq('warned')
      expect(log.reason).to eq('inappropriate')
    end
  end

  describe '#handle_promote_command' do
    let!(:target_user) { create(:user, username: 'target') }

    before do
      allow(user_service).to receive(:promote_user).and_return({ success: true, message: 'User promoted' })
    end

    context 'when user is admin' do
      it 'promotes user successfully' do
        result = handler.send(:handle_promote_command, message, admin, ['@target', 'moderator'])
        
        expect(result).to be true
        expect(user_service).to have_received(:promote_user).with(target_user.telegram_id, 'moderator', admin.telegram_id)
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: '✅ User promoted',
          reply_to_message_id: 123
        )
      end

      it 'rejects invalid roles' do
        result = handler.send(:handle_promote_command, message, admin, ['@target', 'invalid'])
        
        expect(result).to be true
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: '❌ Invalid role',
          reply_to_message_id: 123
        )
      end
    end

    context 'when user is not admin' do
      it 'does not process command' do
        result = handler.send(:handle_promote_command, message, moderator, ['@target', 'moderator'])
        expect(result).to be_nil
      end
    end
  end

  describe '#handle_stats_command' do
    before do
      allow(user_service).to receive(:get_chat_stats).and_return({
        chat_title: 'Test Chat',
        chat_type: 'supergroup',
        moderation_enabled: true,
        total_messages: 100,
        flagged_messages: 5,
        active_users: 10
      })
      
      allow(user_service).to receive(:get_user_stats).and_return({
        username: 'testuser',
        role: 'user',
        status: 'active',
        message_count: 50,
        recent_messages: 5,
        flagged_messages: 0,
        warning_count: 0,
        member_since: Time.current,
        last_interaction: Time.current
      })
    end

    context 'without arguments' do
      it 'returns chat statistics' do
        result = handler.send(:handle_stats_command, message, admin, chat_session, [])
        
        expect(result).to be true
        expect(user_service).to have_received(:get_chat_stats).with(chat_session.chat_id)
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: include('Chat Statistics'),
          reply_to_message_id: 123
        )
      end
    end

    context 'with username argument' do
      let!(:target_user) { create(:user, username: 'target') }

      it 'returns user statistics' do
        result = handler.send(:handle_stats_command, message, admin, chat_session, ['@target'])
        
        expect(result).to be true
        expect(user_service).to have_received(:get_user_stats).with(target_user.telegram_id)
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: include('User Statistics'),
          reply_to_message_id: 123
        )
      end
    end
  end

  describe '#handle_moderation_command' do
    it 'enables moderation' do
      result = handler.send(:handle_moderation_command, message, admin, chat_session, ['on'])
      
      expect(result).to be true
      expect(chat_session.reload.moderation_enabled).to be true
      expect(bot.api).to have_received(:send_message).with(
        chat_id: chat_session.chat_id,
        text: '✅ Moderation enabled for this chat',
        reply_to_message_id: 123
      )
    end

    it 'disables moderation' do
      result = handler.send(:handle_moderation_command, message, admin, chat_session, ['off'])
      
      expect(result).to be true
      expect(chat_session.reload.moderation_enabled).to be false
    end

    it 'shows settings' do
      result = handler.send(:handle_moderation_command, message, admin, chat_session, ['settings'])
      
      expect(result).to be true
      expect(bot.api).to have_received(:send_message).with(
        chat_id: chat_session.chat_id,
        text: include('Moderation Settings'),
        reply_to_message_id: 123
      )
    end
  end

  describe '#handle_cleanup_command' do
    before do
      allow(user_service).to receive(:cleanup_expired_bans).and_return(5)
    end

    context 'when user is admin' do
      it 'cleans up expired bans' do
        result = handler.send(:handle_cleanup_command, message, admin)
        
        expect(result).to be true
        expect(user_service).to have_received(:cleanup_expired_bans)
        expect(bot.api).to have_received(:send_message).with(
          chat_id: chat_session.chat_id,
          text: '🧹 Cleaned up 5 expired bans',
          reply_to_message_id: 123
        )
      end
    end

    context 'when user is not admin' do
      it 'does not process command' do
        result = handler.send(:handle_cleanup_command, message, moderator)
        expect(result).to be_nil
      end
    end
  end

  describe '#extract_username' do
    it 'removes @ prefix from username' do
      result = handler.send(:extract_username, '@testuser')
      expect(result).to eq('testuser')
    end

    it 'returns username as-is if no @ prefix' do
      result = handler.send(:extract_username, 'testuser')
      expect(result).to eq('testuser')
    end
  end
end