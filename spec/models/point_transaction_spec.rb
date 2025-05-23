require 'spec_helper'

RSpec.describe PointTransaction, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user).with_foreign_key(:user_id).with_primary_key(:telegram_id) }
    it { is_expected.to belong_to(:chat_session).with_foreign_key(:chat_id).with_primary_key(:chat_id).optional }
    it { is_expected.to belong_to(:admin_user).class_name('User').with_foreign_key(:admin_id).with_primary_key(:telegram_id).optional }
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:transaction_type).with_values(
        earned: 'earned',
        spent: 'spent',
        admin_given: 'admin_given',
        admin_taken: 'admin_taken',
        message_reward: 'message_reward',
        activity_bonus: 'activity_bonus'
      )
    end
  end

  describe 'scopes' do
    let!(:old_transaction) { create(:point_transaction, created_at: 40.days.ago) }
    let!(:recent_transaction) { create(:point_transaction, created_at: 10.days.ago) }

    describe '.recent' do
      it 'returns transactions from the last 30 days' do
        expect(PointTransaction.recent).to contain_exactly(recent_transaction)
      end
    end
  end
end