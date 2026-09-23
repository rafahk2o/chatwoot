require 'rails_helper'

describe SearchService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, account: account, name: 'Motorista', phone_number: '+551296273723') }
  let!(:conversation) { create(:conversation, contact: contact, inbox: inbox, account: account) }

  before { create(:inbox_member, user: user, inbox: inbox) }

  it 'finds conversations and contacts by phone typed in another format' do
    result = described_class.new(current_user: user, current_account: account, params: { q: '12 99627 3723' }, search_type: 'all').perform

    expect(result[:conversations].map(&:id)).to eq([conversation.id])
    expect(result[:contacts].map(&:id)).to eq([contact.id])
  end
end
