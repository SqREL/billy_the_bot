require 'spec_helper'

RSpec.describe User, type: :model do
  let(:user) { create(:user) }

  describe 'enums' do
    it { is_expected.to define_enum_for(:role).with_values(user: 0, moderator: 1, admin: 2) }
    it { is_expected.to define_enum_for(:status).with_values(active: 0, warned: 1, muted: 2, banned: 3) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:messages).with_foreign_key(:telegram_user_id).with_primary_key(:telegram_id) }
    it { is_expected.to have_many(:moderation_logs).with_foreign_key(:user_id).with_primary_key(:telegram_id) }
    it { is_expected.to have_many(:point_transactions).with_foreign_key(:user_id).with_primary_key(:telegram_id) }
  end

  describe '#banned?' do
    context 'when user is banned with no expiry' do
      let(:user) { create(:user, status: :banned, banned_until: nil) }
      
      it 'returns true' do
        expect(user.banned?).to be true
      end
    end

    context 'when user is banned with future expiry' do
      let(:user) { create(:user, status: :banned, banned_until: 1.hour.from_now) }
      
      it 'returns true' do
        expect(user.banned?).to be true
      end
    end

    context 'when user is banned with past expiry' do
      let(:user) { create(:user, status: :banned, banned_until: 1.hour.ago) }
      
      it 'returns false' do
        expect(user.banned?).to be false
      end
    end

    context 'when user is not banned' do
      let(:user) { create(:user, status: :active) }
      
      it 'returns false' do
        expect(user.banned?).to be false
      end
    end
  end

  describe '#muted?' do
    context 'when user is muted with future expiry' do
      let(:user) { create(:user, status: :muted, banned_until: 1.hour.from_now) }
      
      it 'returns true' do
        expect(user.muted?).to be true
      end
    end

    context 'when user is muted with past expiry' do
      let(:user) { create(:user, status: :muted, banned_until: 1.hour.ago) }
      
      it 'returns false' do
        expect(user.muted?).to be false
      end
    end

    context 'when user is muted with no expiry' do
      let(:user) { create(:user, status: :muted, banned_until: nil) }
      
      it 'returns false' do
        expect(user.muted?).to be false
      end
    end

    context 'when user is not muted' do
      let(:user) { create(:user, status: :active) }
      
      it 'returns false' do
        expect(user.muted?).to be false
      end
    end
  end

  describe '#can_send_messages?' do
    context 'when user is active and not banned' do
      let(:user) { create(:user, status: :active) }
      
      it 'returns true' do
        expect(user.can_send_messages?).to be true
      end
    end

    context 'when user is banned' do
      let(:user) { create(:user, status: :banned) }
      
      it 'returns false' do
        expect(user.can_send_messages?).to be false
      end
    end

    context 'when user is not active' do
      let(:user) { create(:user, status: :muted) }
      
      it 'returns false' do
        expect(user.can_send_messages?).to be false
      end
    end
  end

  describe '#increment_warnings!' do
    context 'when user has no warnings' do
      let(:user) { create(:user, warning_count: 0) }
      
      it 'increments warning count and sets status to warned' do
        user.increment_warnings!
        expect(user.warning_count).to eq(1)
        expect(user.status).to eq('warned')
      end
    end

    context 'when user has 1 warning' do
      let(:user) { create(:user, warning_count: 1) }
      
      it 'increments warning count and mutes user for 1 hour' do
        user.increment_warnings!
        expect(user.warning_count).to eq(2)
        expect(user.status).to eq('muted')
        expect(user.banned_until).to be_within(1.minute).of(1.hour.from_now)
      end
    end

    context 'when user has 2 warnings' do
      let(:user) { create(:user, warning_count: 2) }
      
      it 'increments warning count and bans user for 24 hours' do
        user.increment_warnings!
        expect(user.warning_count).to eq(3)
        expect(user.status).to eq('banned')
        expect(user.banned_until).to be_within(1.minute).of(24.hours.from_now)
      end
    end

    context 'when user has 3 or more warnings' do
      let(:user) { create(:user, warning_count: 3) }
      
      it 'increments warning count and permanently bans user' do
        user.increment_warnings!
        expect(user.warning_count).to eq(4)
        expect(user.status).to eq('banned')
        expect(user.banned_until).to be_nil
      end
    end
  end

  describe '#add_points' do
    let(:admin) { create(:user, :admin) }
    let(:chat_session) { create(:chat_session) }
    
    context 'when adding positive points' do
      it 'increases user points and creates transaction' do
        expect {
          user.add_points(10, 'Test reward', admin.telegram_id, chat_session.chat_id)
        }.to change { user.points }.by(10)
         .and change { user.total_points_earned }.by(10)
         .and change { PointTransaction.count }.by(1)
        
        transaction = PointTransaction.last
        expect(transaction.amount).to eq(10)
        expect(transaction.transaction_type).to eq('admin_given')
        expect(transaction.reason).to eq('Test reward')
      end
    end

    context 'when removing points' do
      let(:user) { create(:user, points: 20) }
      
      it 'decreases user points and creates transaction' do
        expect {
          user.add_points(-5, 'Test penalty', admin.telegram_id, chat_session.chat_id)
        }.to change { user.points }.by(-5)
         .and change { user.total_points_spent }.by(5)
         .and change { PointTransaction.count }.by(1)
        
        transaction = PointTransaction.last
        expect(transaction.amount).to eq(-5)
        expect(transaction.transaction_type).to eq('admin_taken')
      end
    end
  end

  describe '#recent_points_activity' do
    let(:user) { create(:user) }
    
    before do
      create(:point_transaction, user: user, created_at: 2.days.ago)
      create(:point_transaction, user: user, created_at: 40.days.ago)
      create(:point_transaction, user: user, created_at: 1.day.ago)
    end
    
    it 'returns transactions from last 30 days in descending order' do
      activity = user.recent_points_activity
      expect(activity.count).to eq(2)
      expect(activity.first.created_at).to be > activity.last.created_at
    end
    
    it 'accepts custom number of days' do
      activity = user.recent_points_activity(50)
      expect(activity.count).to eq(3)
    end
  end

  describe '#display_name' do
    context 'when user has username' do
      let(:user) { create(:user, username: 'testuser', first_name: 'John') }
      
      it 'returns username with @' do
        expect(user.display_name).to eq('@testuser')
      end
    end

    context 'when user has first_name but no username' do
      let(:user) { create(:user, username: nil, first_name: 'John') }
      
      it 'returns first_name' do
        expect(user.display_name).to eq('John')
      end
    end

    context 'when user has neither username nor first_name' do
      let(:user) { create(:user, username: nil, first_name: nil, telegram_id: 12345) }
      
      it 'returns User with telegram_id' do
        expect(user.display_name).to eq('User 12345')
      end
    end
  end
end