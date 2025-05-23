require 'spec_helper'

RSpec.describe MessageTemplate, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:creator).class_name('User').with_foreign_key(:created_by).with_primary_key(:telegram_id).optional }
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:template_type).with_values(
        text: 'text',
        poll: 'poll',
        quiz: 'quiz',
        photo: 'photo',
        announcement: 'announcement'
      )
    end
  end

  describe 'scopes' do
    let!(:active_template) { create(:message_template, active: true) }
    let!(:inactive_template) { create(:message_template, active: false) }

    describe '.active' do
      it 'returns only active templates' do
        expect(MessageTemplate.active).to contain_exactly(active_template)
      end
    end
  end

  describe '#parsed_options' do
    context 'when options contains valid JSON' do
      let(:template) { create(:message_template, options: '["option1", "option2", "option3"]') }
      
      it 'returns parsed array' do
        expect(template.parsed_options).to eq(['option1', 'option2', 'option3'])
      end
    end

    context 'when options contains invalid JSON' do
      let(:template) { create(:message_template, options: 'invalid json') }
      
      it 'returns empty array' do
        expect(template.parsed_options).to eq([])
      end
    end

    context 'when options is nil or empty' do
      let(:template) { create(:message_template, options: nil) }
      
      it 'returns empty array' do
        expect(template.parsed_options).to eq([])
      end
    end
  end

  describe '#set_options' do
    let(:template) { create(:message_template) }
    
    it 'sets options as JSON string' do
      options_array = ['opt1', 'opt2', 'opt3']
      template.set_options(options_array)
      expect(template.options).to eq(options_array.to_json)
    end
    
    it 'works with empty array' do
      template.set_options([])
      expect(template.options).to eq('[]')
    end
  end
end