require 'spec_helper'

RSpec.describe ChatSession, type: :model do
  let(:chat_session) { create(:chat_session) }

  describe 'associations' do
    it { is_expected.to have_many(:messages).with_foreign_key(:telegram_chat_id).with_primary_key(:chat_id) }
    it { is_expected.to have_many(:point_transactions).with_foreign_key(:chat_id).with_primary_key(:chat_id) }
  end

  describe '#moderation_enabled?' do
    context 'when moderation is enabled' do
      let(:chat_session) { create(:chat_session, moderation_enabled: true) }
      
      it 'returns true' do
        expect(chat_session.moderation_enabled?).to be true
      end
    end

    context 'when moderation is disabled' do
      let(:chat_session) { create(:chat_session, moderation_enabled: false) }
      
      it 'returns false' do
        expect(chat_session.moderation_enabled?).to be false
      end
    end
  end

  describe '#get_setting' do
    let(:chat_session) { create(:chat_session, settings: { 'test_key' => 'test_value', 'number_key' => 42 }) }
    
    it 'returns the setting value when key exists' do
      expect(chat_session.get_setting('test_key')).to eq('test_value')
      expect(chat_session.get_setting(:test_key)).to eq('test_value')
    end
    
    it 'returns default value when key does not exist' do
      expect(chat_session.get_setting('missing_key', 'default')).to eq('default')
    end
    
    it 'returns nil when key does not exist and no default provided' do
      expect(chat_session.get_setting('missing_key')).to be_nil
    end
    
    context 'when settings is nil' do
      let(:chat_session) { create(:chat_session, settings: nil) }
      
      it 'returns default value' do
        expect(chat_session.get_setting('any_key', 'default')).to eq('default')
      end
    end
  end

  describe '#set_setting' do
    let(:chat_session) { create(:chat_session, settings: {}) }
    
    it 'sets the setting value and saves' do
      chat_session.set_setting('new_key', 'new_value')
      expect(chat_session.settings['new_key']).to eq('new_value')
      expect(chat_session.reload.settings['new_key']).to eq('new_value')
    end
    
    it 'works with symbol keys' do
      chat_session.set_setting(:symbol_key, 'symbol_value')
      expect(chat_session.settings['symbol_key']).to eq('symbol_value')
    end
    
    it 'initializes settings hash if nil' do
      chat_session.update!(settings: nil)
      chat_session.set_setting('test_key', 'test_value')
      expect(chat_session.settings).to eq({ 'test_key' => 'test_value' })
    end
  end

  describe '#display_name' do
    context 'when chat has title' do
      let(:chat_session) { create(:chat_session, chat_title: 'My Test Chat', chat_id: -12345) }
      
      it 'returns the chat title' do
        expect(chat_session.display_name).to eq('My Test Chat')
      end
    end

    context 'when chat has no title' do
      let(:chat_session) { create(:chat_session, chat_title: nil, chat_id: -12345) }
      
      it 'returns Chat with chat_id' do
        expect(chat_session.display_name).to eq('Chat -12345')
      end
    end
  end
end