import { frontendURL } from '../../../helper/URLHelper';
import ConversationBoard from './ConversationBoard.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/board'),
    name: 'conversation_board',
    component: ConversationBoard,
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
