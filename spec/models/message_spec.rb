require 'spec_helper'

RSpec.describe Message, type: :model do
  let(:message) { create(:message) }

  describe 'associations' do
    it { is_expected.to belong_to(:user).with_foreign_key(:telegram_user_id).with_primary_key(:telegram_id) }
    it { is_expected.to belong_to(:chat_session).with_foreign_key(:telegram_chat_id).with_primary_key(:chat_id) }
  end

  describe 'scopes' do
    let!(:flagged_message) { create(:message, :flagged, created_at: 2.hours.ago) }
    let!(:normal_message) { create(:message, created_at: 2.hours.ago) }
    let!(:old_message) { create(:message, created_at: 2.hours.ago) }
    let!(:recent_message) { create(:message, created_at: 30.minutes.ago) }

    describe '.flagged' do
      it 'returns only flagged messages' do
        expect(Message.flagged).to contain_exactly(flagged_message)
      end
    end

    describe '.recent' do
      it 'returns messages from the last hour' do
        expect(Message.recent).to contain_exactly(recent_message)
      end
    end
  end

  describe '#violent?' do
    context 'when violence_score is above threshold' do
      let(:message) { create(:message, violence_score: 0.9) }
      
      it 'returns true' do
        expect(message.violent?).to be true
      end
    end

    context 'when violence_score is below threshold' do
      let(:message) { create(:message, violence_score: 0.5) }
      
      it 'returns false' do
        expect(message.violent?).to be false
      end
    end

    context 'when violence_score is nil' do
      let(:message) { create(:message, violence_score: nil) }
      
      it 'returns false' do
        expect(message.violent?).to be false
      end
    end
  end

  describe '#toxic?' do
    context 'when toxicity_score is above threshold' do
      let(:message) { create(:message, toxicity_score: 0.8) }
      
      it 'returns true' do
        expect(message.toxic?).to be true
      end
    end

    context 'when toxicity_score is below threshold' do
      let(:message) { create(:message, toxicity_score: 0.5) }
      
      it 'returns false' do
        expect(message.toxic?).to be false
      end
    end

    context 'when toxicity_score is nil' do
      let(:message) { create(:message, toxicity_score: nil) }
      
      it 'returns false' do
        expect(message.toxic?).to be false
      end
    end
  end
end