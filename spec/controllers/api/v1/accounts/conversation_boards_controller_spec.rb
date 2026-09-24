require 'rails_helper'

RSpec.describe 'Conversation board API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Agent') }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:board_url) { "/api/v1/accounts/#{account.id}/conversation_board" }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def board_ids(user, params = {})
    get board_url, params: params, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['conversations'].pluck('id')
  end

  it 'requires authentication' do
    get board_url
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lists open and pending conversations with agents and their inboxes' do
    open = create(:conversation, account: account, inbox: inbox, assignee: agent)
    pending = create(:conversation, account: account, inbox: inbox, status: :pending)
    create(:conversation, account: account, inbox: inbox, status: :resolved)
    create(:message, conversation: open, account: account, inbox: inbox, content: 'última mensagem')

    get board_url, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['conversations'].pluck('id')).to contain_exactly(open.display_id, pending.display_id)
    expect(body['conversations'].find { |c| c['id'] == open.display_id }['last_message']['content']).to eq('última mensagem')
    expect(body['agents'].find { |a| a['id'] == agent.id }['inbox_ids']).to eq([inbox.id])
  end

  it 'shows agents only conversations from inboxes they belong to' do
    visible = create(:conversation, account: account, inbox: inbox)
    create(:conversation, account: account, inbox: other_inbox)

    expect(board_ids(agent)).to eq([visible.display_id])
  end

  it 'limits columns and cards to the selected team' do
    team = create(:team, account: account)
    create(:team_member, team: team, user: agent)
    outsider = create(:user, account: account, role: :agent)
    create(:inbox_member, user: outsider, inbox: other_inbox)

    team_card = create(:conversation, account: account, inbox: inbox, assignee: agent)
    unassigned_in_team_inbox = create(:conversation, account: account, inbox: inbox)
    create(:conversation, account: account, inbox: other_inbox, assignee: outsider)
    create(:conversation, account: account, inbox: other_inbox)

    ids = board_ids(admin, team_id: team.id)

    expect(ids).to contain_exactly(team_card.display_id, unassigned_in_team_inbox.display_id)
    body = response.parsed_body
    # The viewer keeps their own column even outside the team
    expect(body['agents'].pluck('id')).to contain_exactly(admin.id, agent.id)
    # The move dialog can still reach agents outside the selected team
    expect(body['directory'].pluck('id')).to include(agent.id, outsider.id, admin.id)
    expect(body['teams'].find { |t| t['id'] == team.id }['member_ids']).to eq([agent.id])
  end

  describe 'pinning and manual order' do
    let!(:first) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
    let!(:second) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

    def card(id)
      get board_url, headers: admin.create_new_auth_token, as: :json
      response.parsed_body['conversations'].find { |c| c['id'] == id }
    end

    it 'pins a card and unpins it once the conversation changes column' do
      post "#{board_url}/pin", params: { conversation_id: first.display_id, pinned: true },
                               headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(card(first.display_id)['pinned']).to be(true)

      first.update!(assignee: admin)
      expect(card(first.display_id)['pinned']).to be(false)
    end

    it 'saves the order of a column' do
      post "#{board_url}/reorder", params: { conversation_ids: [second.display_id, first.display_id] },
                                   headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      expect(card(second.display_id)['position']).to eq(0)
      expect(card(first.display_id)['position']).to eq(1)
    end

    it 'does not let agents pin conversations they cannot see' do
      hidden = create(:conversation, account: account, inbox: other_inbox)
      post "#{board_url}/pin", params: { conversation_id: hidden.display_id, pinned: true },
                               headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
