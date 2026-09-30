/* global axios */
import ApiClient from './ApiClient';

// Melck fork: conversations the current user pinned to the top of the list.
class ConversationPinsAPI extends ApiClient {
  constructor() {
    super('conversation_pins', { accountScoped: true });
  }

  pin(conversationId) {
    return axios.post(this.url, { conversation_id: conversationId });
  }
}

export default new ConversationPinsAPI();
