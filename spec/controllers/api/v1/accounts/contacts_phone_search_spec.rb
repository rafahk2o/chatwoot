require 'rails_helper'

RSpec.describe 'Contacts API phone search', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:contact) { create(:contact, account: account, name: 'Motorista', phone_number: '+551296273723') }

  before { create(:contact, account: account, name: 'Outro', phone_number: '+5541997166249') }

  it 'finds the contact by phone typed in another format' do
    get "/api/v1/accounts/#{account.id}/contacts/search",
        params: { q: '(12) 99627-3723' },
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].pluck('id')).to eq([contact.id])
  end
end
