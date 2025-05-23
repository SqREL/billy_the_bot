require 'spec_helper'

RSpec.describe PointsService do
  let(:user) { create(:user, points: 100) }
  let(:admin) { create(:user, :admin) }
  let(:chat_session) { create(:chat_session) }

  describe '.award_points' do
    context 'with valid amount' do
      it 'awards points and creates moderation log when admin_id provided' do
        result = PointsService.award_points(user, 50, 'Good behavior', admin.telegram_id, chat_session.chat_id)
        
        expect(result[:success]).to be true
        expect(result[:message]).to include('Awarded 50 points')
        expect(result[:new_total]).to eq(150)
        expect(user.reload.points).to eq(150)
        
        log = ModerationLog.last
        expect(log.action).to eq('points_given')
        expect(log.user_id).to eq(user.telegram_id)
        expect(log.moderator_id).to eq(admin.telegram_id)
      end

      it 'awards points without moderation log when no admin_id' do
        result = PointsService.award_points(user, 30, 'Daily bonus')
        
        expect(result[:success]).to be true
        expect(user.reload.points).to eq(130)
        expect(ModerationLog.count).to eq(0)
      end
    end

    context 'with invalid amount' do
      it 'returns error for zero amount' do
        result = PointsService.award_points(user, 0, 'Invalid')
        expect(result[:success]).to be false
        expect(result[:message]).to eq('Invalid amount')
      end

      it 'returns error for negative amount' do
        result = PointsService.award_points(user, -10, 'Invalid')
        expect(result[:success]).to be false
        expect(result[:message]).to eq('Invalid amount')
      end
    end
  end

  describe '.deduct_points' do
    context 'with valid amount and sufficient points' do
      it 'deducts points and creates moderation log' do
        result = PointsService.deduct_points(user, 25, 'Violation', admin.telegram_id, chat_session.chat_id)
        
        expect(result[:success]).to be true
        expect(result[:message]).to include('Deducted 25 points')
        expect(result[:new_total]).to eq(75)
        expect(user.reload.points).to eq(75)
        
        log = ModerationLog.last
        expect(log.action).to eq('points_taken')
      end
    end

    context 'with insufficient points' do
      it 'returns error' do
        result = PointsService.deduct_points(user, 150, 'Too much')
        expect(result[:success]).to be false
        expect(result[:message]).to eq('Insufficient points')
        expect(user.reload.points).to eq(100)
      end
    end

    context 'with invalid amount' do
      it 'returns error for zero amount' do
        result = PointsService.deduct_points(user, 0, 'Invalid')
        expect(result[:success]).to be false
        expect(result[:message]).to eq('Invalid amount')
      end
    end
  end

  describe '.reward_activity' do
    context 'for message_sent activity' do
      it 'rewards points for first message in hour' do
        reward = PointsService.reward_activity(user, :message_sent, chat_session.chat_id)
        
        expect(reward).to eq(1)
        expect(user.reload.points).to eq(101)
        
        transaction = PointTransaction.last
        expect(transaction.transaction_type).to eq('message_reward')
        expect(transaction.amount).to eq(1)
      end

      it 'does not reward for subsequent messages within hour' do
        create(:point_transaction, 
               user: user, 
               transaction_type: :message_reward, 
               created_at: 30.minutes.ago)
        
        reward = PointsService.reward_activity(user, :message_sent, chat_session.chat_id)
        expect(reward).to be_nil
        expect(user.reload.points).to eq(100)
      end
    end

    context 'for other activities' do
      it 'rewards daily activity points' do
        reward = PointsService.reward_activity(user, :daily_activity, chat_session.chat_id)
        
        expect(reward).to eq(10)
        expect(user.reload.points).to eq(110)
        
        transaction = PointTransaction.last
        expect(transaction.transaction_type).to eq('activity_bonus')
      end
    end

    context 'for unknown activity' do
      it 'returns nil' do
        reward = PointsService.reward_activity(user, :unknown_activity, chat_session.chat_id)
        expect(reward).to be_nil
        expect(user.reload.points).to eq(100)
      end
    end
  end

  describe '.get_leaderboard' do
    let!(:top_user) { create(:user, points: 1000) }
    let!(:mid_user) { create(:user, points: 500) }
    let!(:bottom_user) { create(:user, points: 100) }
    let!(:low_user) { create(:user, points: 0) }

    it 'returns users ordered by points descending' do
      leaderboard = PointsService.get_leaderboard
      expect(leaderboard.pluck(:points)).to eq([1000, 500, 100])
    end

    it 'excludes users with zero points' do
      leaderboard = PointsService.get_leaderboard
      expect(leaderboard).not_to include(low_user)
    end

    it 'respects limit parameter' do
      leaderboard = PointsService.get_leaderboard(nil, 2)
      expect(leaderboard.count).to eq(2)
    end
  end

  describe '.get_user_rank' do
    let!(:better_user1) { create(:user, points: 200) }
    let!(:better_user2) { create(:user, points: 150) }
    let!(:worse_user) { create(:user, points: 50) }

    it 'returns correct rank based on points' do
      rank = PointsService.get_user_rank(user)
      expect(rank).to eq(3) # Two users have more points
    end
  end

  describe '.transfer_points' do
    let(:recipient) { create(:user, points: 50) }

    context 'with valid transfer' do
      it 'transfers points between users' do
        result = PointsService.transfer_points(user, recipient, 25, 'Gift')
        
        expect(result[:success]).to be true
        expect(user.reload.points).to eq(75)
        expect(recipient.reload.points).to eq(75)
        
        sender_transaction = PointTransaction.where(user_id: user.telegram_id, amount: -25).first
        expect(sender_transaction.transaction_type).to eq('spent')
        
        recipient_transaction = PointTransaction.where(user_id: recipient.telegram_id, amount: 25).first
        expect(recipient_transaction.transaction_type).to eq('earned')
      end
    end

    context 'with invalid transfer' do
      it 'fails when insufficient points' do
        result = PointsService.transfer_points(user, recipient, 150, 'Too much')
        expect(result[:success]).to be false
        expect(result[:message]).to eq('Insufficient points')
      end

      it 'fails when transferring to self' do
        result = PointsService.transfer_points(user, user, 25, 'Self transfer')
        expect(result[:success]).to be false
        expect(result[:message]).to eq('Cannot transfer to yourself')
      end

      it 'fails with invalid amount' do
        result = PointsService.transfer_points(user, recipient, 0, 'Zero')
        expect(result[:success]).to be false
        expect(result[:message]).to eq('Invalid amount')
      end
    end
  end

  describe '.calculate_daily_bonus' do
    it 'calculates bonus based on consecutive days' do
      user = create(:user)
      # Create messages for consecutive days including today
      create(:message, user: user, created_at: Time.current)
      create(:message, user: user, created_at: 1.day.ago)
      create(:message, user: user, created_at: 2.days.ago)
      
      bonus = PointsService.calculate_daily_bonus(user)
      expect(bonus).to eq(15) # 3 days * 5 points each
    end

    context 'with week streak' do
      it 'calculates week bonus correctly' do
        user = create(:user)
        # Create messages for 8 consecutive days (0-7 days ago)
        (0..7).each do |days_ago|
          create(:message, user: user, created_at: days_ago.days.ago)
        end
        
        bonus = PointsService.calculate_daily_bonus(user)
        expect(bonus).to eq(45) # 35 (week) + 10 (8th day)
      end
    end
  end
end