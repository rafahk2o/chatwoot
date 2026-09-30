// Melck fork: conversations the current user pinned to the top of the list.
import ConversationPinsAPI from 'dashboard/api/conversationPins';

export const SET_PINNED_CONVERSATIONS = 'SET_PINNED_CONVERSATIONS';

export const state = {
  ids: [],
};

export const getters = {
  isPinned: $state => conversationId => $state.ids.includes(conversationId),
};

export const actions = {
  async fetch({ commit }) {
    const { data } = await ConversationPinsAPI.get();
    commit(SET_PINNED_CONVERSATIONS, data.payload);
  },
  async toggle({ commit, state: currentState }, conversationId) {
    const previousIds = currentState.ids;
    const pinned = previousIds.includes(conversationId);
    commit(
      SET_PINNED_CONVERSATIONS,
      pinned
        ? previousIds.filter(id => id !== conversationId)
        : [...previousIds, conversationId]
    );
    try {
      if (pinned) {
        await ConversationPinsAPI.delete(conversationId);
      } else {
        await ConversationPinsAPI.pin(conversationId);
      }
    } catch (error) {
      commit(SET_PINNED_CONVERSATIONS, previousIds);
      throw error;
    }
  },
};

export const mutations = {
  [SET_PINNED_CONVERSATIONS]($state, ids) {
    $state.ids = ids;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
