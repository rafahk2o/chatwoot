import { frontendURL } from '../../../helper/URLHelper';
import ConversationBoard from './ConversationBoard.vue';
import ConversationBoardTv from './ConversationBoardTv.vue';

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

// Full screen, outside the dashboard layout (no sidebar), for a wall monitor.
export const tvRoutes = [
  {
    path: frontendURL('accounts/:accountId/board/tv'),
    name: 'conversation_board_tv',
    component: ConversationBoardTv,
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
