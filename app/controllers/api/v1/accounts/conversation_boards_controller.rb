# Melck fork: data for the conversation board, a Kanban with one column per
# agent where dragging a card reassigns the conversation (via the regular
# assignments endpoint).
#
# Columns are the agents of the selected team (or everyone). Cards are the open
# and pending conversations the current user can see, assigned to one of those
# agents or unassigned in an inbox they work in. `directory` lists every agent
# and `teams` their members, so a card can be moved to any team from a dialog.
class Api::V1::Accounts::ConversationBoardsController < Api::V1::Accounts::BaseController
  STATUSES = %w[open pending].freeze
  LIMIT = 1500

  def show
    conversations = board_conversations.to_a
    render json: {
      teams: teams_payload,
      agents: agents.map { |agent| agent_payload(agent) },
      directory: all_agents.map { |agent| agent_payload(agent) },
      conversations: conversations_payload(conversations),
      truncated: conversations.size >= LIMIT
    }
  end

  private

  def team
    return if params[:team_id].blank?

    @team ||= Current.account.teams.find(params[:team_id])
  end

  def all_agents
    @all_agents ||= Current.account.users.order(:name).to_a
  end

  def agents
    return all_agents unless team

    @agents ||= all_agents.select { |agent| team_member_ids.include?(agent.id) }
  end

  def team_member_ids
    @team_member_ids ||= team.team_members.pluck(:user_id)
  end

  def teams_payload
    Current.account.teams.includes(:team_members).order(:name).map do |t|
      { id: t.id, name: t.name, member_ids: t.team_members.map(&:user_id) }
    end
  end

  def account_users
    @account_users ||= Current.account.account_users.where(user_id: all_agents.map(&:id)).index_by(&:user_id)
  end

  def inbox_ids_by_agent
    @inbox_ids_by_agent ||= InboxMember.joins(:inbox)
                                       .where(user_id: all_agents.map(&:id), inboxes: { account_id: Current.account.id })
                                       .pluck(:user_id, :inbox_id)
                                       .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  def board_conversations
    scope = Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform
    scope = scope.where(status: STATUSES)
    if team
      team_inbox_ids = agents.flat_map { |agent| inbox_ids_by_agent.fetch(agent.id, []) }.uniq
      scope = scope.where(assignee_id: agents.map(&:id)).or(scope.where(assignee_id: nil, inbox_id: team_inbox_ids))
    end
    scope.includes(:contact, :inbox).order(last_activity_at: :desc).limit(LIMIT)
  end

  def agent_payload(agent)
    account_user = account_users[agent.id]
    {
      id: agent.id,
      name: agent.available_name,
      thumbnail: agent.avatar_url,
      role: account_user&.role,
      availability_status: account_user&.availability,
      inbox_ids: inbox_ids_by_agent.fetch(agent.id, [])
    }
  end

  def conversations_payload(conversations)
    last_messages = last_messages_for(conversations.map(&:id))
    conversations.map { |conversation| card_payload(conversation, last_messages[conversation.id]) }
  end

  def card_payload(conversation, last_message)
    {
      id: conversation.display_id,
      status: conversation.status,
      assignee_id: conversation.assignee_id,
      inbox_id: conversation.inbox_id,
      inbox_name: conversation.inbox.name,
      contact: contact_payload(conversation.contact),
      labels: conversation.cached_label_list.to_s.split(',').map(&:strip).compact_blank,
      last_activity_at: conversation.last_activity_at.to_i,
      waiting_since: conversation.waiting_since&.to_i,
      last_message: last_message && { content: last_message.content.to_s.truncate(140), incoming: last_message.incoming? }
    }
  end

  def contact_payload(contact)
    return {} if contact.nil?

    { name: contact.name, phone_number: contact.phone_number, thumbnail: contact.avatar_url }
  end

  def last_messages_for(conversation_ids)
    return {} if conversation_ids.empty?

    Message.where(conversation_id: conversation_ids, message_type: %i[incoming outgoing], private: false)
           .select('DISTINCT ON (conversation_id) conversation_id, content, message_type, created_at')
           .reorder(:conversation_id, created_at: :desc) # Message has a default created_at ASC order
           .index_by(&:conversation_id)
  end
end
