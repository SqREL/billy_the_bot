require 'spec_helper'

RSpec.describe AdminSession, type: :model do
  describe '.cleanup_expired' do
    let!(:expired_session) { create(:admin_session, expires_at: 1.hour.ago) }
    let!(:valid_session) { create(:admin_session, expires_at: 1.hour.from_now) }
    
    it 'deletes expired sessions' do
      expect { AdminSession.cleanup_expired }.to change { AdminSession.count }.by(-1)
      expect(AdminSession.exists?(expired_session.id)).to be false
      expect(AdminSession.exists?(valid_session.id)).to be true
    end
  end

  describe '#expired?' do
    context 'when expires_at is in the past' do
      let(:session) { create(:admin_session, expires_at: 1.hour.ago) }
      
      it 'returns true' do
        expect(session.expired?).to be true
      end
    end

    context 'when expires_at is in the future' do
      let(:session) { create(:admin_session, expires_at: 1.hour.from_now) }
      
      it 'returns false' do
        expect(session.expired?).to be false
      end
    end
  end

  describe '#extend_session!' do
    let(:session) { create(:admin_session, expires_at: 1.hour.from_now) }
    
    it 'extends session by 24 hours by default' do
      session.extend_session!
      expect(session.expires_at).to be_within(1.minute).of(24.hours.from_now)
    end
    
    it 'extends session by custom hours' do
      session.extend_session!(48)
      expect(session.expires_at).to be_within(1.minute).of(48.hours.from_now)
    end
  end
end