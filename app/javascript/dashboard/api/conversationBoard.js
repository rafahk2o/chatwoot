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
}

export default new ConversationBoardAPI();
