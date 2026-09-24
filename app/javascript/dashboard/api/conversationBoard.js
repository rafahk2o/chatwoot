/* global axios */
import ApiClient from './ApiClient';

// Melck fork: data for the conversation board (Kanban by agent).
class ConversationBoardAPI extends ApiClient {
  constructor() {
    super('conversation_board', { accountScoped: true });
  }

  get({ teamId } = {}) {
    return axios.get(this.url, { params: { team_id: teamId || undefined } });
  }

  pin({ conversationId, pinned }) {
    return axios.post(`${this.url}/pin`, {
      conversation_id: conversationId,
      pinned,
    });
  }

  // conversationIds: one column, top to bottom
  reorder({ conversationIds }) {
    return axios.post(`${this.url}/reorder`, {
      conversation_ids: conversationIds,
    });
  }
}

export default new ConversationBoardAPI();
