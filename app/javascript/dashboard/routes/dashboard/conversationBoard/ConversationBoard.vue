<script setup>
// Melck fork: Kanban with one column per agent. Dragging a card to another
// column reassigns the conversation through the regular assignments endpoint.
// Column order: the current user's own conversations, then the unassigned
// ones, then everyone else. Clicking a card opens the conversation in a modal
// so the agent can reply and resolve without leaving the board. Cards are
// prioritised by how long the contact has been waiting for a reply; pinned
// cards sit above them in a manual order shared by everyone.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import ConversationBoardAPI from 'dashboard/api/conversationBoard';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MoveConversationDialog from './MoveConversationDialog.vue';
import ConversationModal from './ConversationModal.vue';

const UNASSIGNED = 'unassigned';
const TEAM_STORAGE_KEY = 'melck.conversationBoard.teamId';
const POLL_INTERVAL = 60000;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const currentUserId = useMapGetter('getCurrentUserID');

const readStoredTeam = () => {
  try {
    return window.localStorage.getItem(TEAM_STORAGE_KEY) || '';
  } catch {
    return '';
  }
};

const teams = ref([]);
const agents = ref([]);
const directory = ref([]);
const moveDialogRef = ref(null);
const conversationModalRef = ref(null);
const conversations = ref([]);
const truncated = ref(false);
const teamId = ref(readStoredTeam());
const search = ref('');
const isLoading = ref(true);
const hasError = ref(false);
const isDragging = ref(false);
const columnCards = ref({});

// Every agent in the account, not only the current columns: cards can be
// moved to other teams through the move dialog.
const directoryById = computed(() =>
  Object.fromEntries(directory.value.map(agent => [agent.id, agent]))
);

const columns = computed(() => {
  const mine = agents.value.find(agent => agent.id === currentUserId.value);
  const others = agents.value.filter(agent => agent !== mine);
  return [
    ...(mine ? [{ key: String(mine.id), agent: mine, isMine: true }] : []),
    { key: UNASSIGNED, agent: null },
    ...others.map(agent => ({ key: String(agent.id), agent })),
  ];
});

const matchesSearch = conversation => {
  const query = search.value.trim().toLowerCase();
  if (!query) return true;
  const { name = '', phone_number: phone = '' } = conversation.contact || {};
  const digits = query.replace(/\D/g, '');
  return (
    (name || '').toLowerCase().includes(query) ||
    (digits.length >= 4 && (phone || '').replace(/\D/g, '').includes(digits))
  );
};

const columnKeyFor = conversation =>
  conversation.assignee_id ? String(conversation.assignee_id) : UNASSIGNED;

// Pinned cards first, in their manual order. Then the longest wait for a
// reply on top, and last the cards nobody is waiting on, most recent activity
// first (the order the API returns them in).
const byBoardOrder = (a, b) => {
  if (a.pinned || b.pinned) {
    return (
      Number(!!b.pinned) - Number(!!a.pinned) ||
      (a.position ?? Infinity) - (b.position ?? Infinity)
    );
  }
  return (
    (a.waiting_since ?? Infinity) - (b.waiting_since ?? Infinity) ||
    a.fetchIndex - b.fetchIndex
  );
};

// vuedraggable needs plain mutable arrays per column; rebuild them from the
// fetched conversations whenever the data or the search changes.
const rebuildColumns = () => {
  const grouped = Object.fromEntries(columns.value.map(col => [col.key, []]));
  conversations.value.filter(matchesSearch).forEach(conversation => {
    grouped[columnKeyFor(conversation)]?.push(conversation);
  });
  Object.values(grouped).forEach(cards => cards.sort(byBoardOrder));
  columnCards.value = grouped;
};

const fetchBoard = async () => {
  if (isDragging.value) return;
  try {
    const { data } = await ConversationBoardAPI.get({ teamId: teamId.value });
    teams.value = data.teams;
    agents.value = data.agents;
    directory.value = data.directory;
    conversations.value = data.conversations.map((conversation, index) => ({
      ...conversation,
      fetchIndex: index,
    }));
    truncated.value = data.truncated;
    hasError.value = false;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
    rebuildColumns();
  }
};

const scheduleRefresh = debounce(fetchBoard, 1500);

watch(teamId, value => {
  try {
    window.localStorage.setItem(TEAM_STORAGE_KEY, value || '');
  } catch {
    // Browser storage can be unavailable; the filter just won't be remembered.
  }
  isLoading.value = true;
  fetchBoard();
});
watch(search, rebuildColumns);

let pollTimer;
onMounted(() => {
  fetchBoard();
  emitter.on('fetch_conversation_stats', scheduleRefresh);
  pollTimer = setInterval(fetchBoard, POLL_INTERVAL);
});
onBeforeUnmount(() => {
  emitter.off('fetch_conversation_stats', scheduleRefresh);
  clearInterval(pollTimer);
});

const canReceive = (agent, conversation) =>
  !agent ||
  agent.role === 'administrator' ||
  agent.inbox_ids.includes(conversation.inbox_id);

const checkMove = event => {
  const target = directoryById.value[event.to.dataset.column];
  return canReceive(target, event.draggedContext.element);
};

const transfer = async (conversation, agent) => {
  if (!canReceive(agent, conversation)) {
    useAlert(
      t('CONVERSATION_BOARD.NOT_INBOX_MEMBER', {
        name: agent.name,
        inbox: conversation.inbox_name,
      })
    );
    rebuildColumns();
    return;
  }
  try {
    await ConversationAPI.assignAgent({
      conversationId: conversation.id,
      agentId: agent ? agent.id : null,
    });
    conversation.assignee_id = agent ? agent.id : null;
    // A saved position belongs to the old column.
    conversation.pinned = false;
    conversation.position = null;
    useAlert(
      agent
        ? t('CONVERSATION_BOARD.TRANSFERRED', {
            id: conversation.id,
            name: agent.name,
          })
        : t('CONVERSATION_BOARD.UNASSIGNED_DONE', { id: conversation.id })
    );
  } catch {
    useAlert(t('CONVERSATION_BOARD.TRANSFER_ERROR', { id: conversation.id }));
  } finally {
    rebuildColumns();
  }
};

const saveColumnOrder = async columnKey => {
  if (search.value.trim()) {
    // A filtered column is only part of the queue; its order can't be saved.
    useAlert(t('CONVERSATION_BOARD.ORDER.CLEAR_SEARCH'));
    rebuildColumns();
    return;
  }
  // Only pinned cards keep a manual order; the rest follow the waiting time,
  // so an unpinned card dragged elsewhere goes back to its place.
  const cards = (columnCards.value[columnKey] || []).filter(
    card => card.pinned
  );
  cards.forEach((card, index) => {
    card.position = index;
  });
  rebuildColumns();
  if (!cards.length) return;
  try {
    await ConversationBoardAPI.reorder({
      conversationIds: cards.map(card => card.id),
    });
  } catch {
    useAlert(t('CONVERSATION_BOARD.ORDER.ERROR'));
    fetchBoard();
  }
};

const onColumnChange = (columnKey, event) => {
  if (event.added) {
    transfer(event.added.element, directoryById.value[columnKey] || null);
  } else if (event.moved) {
    saveColumnOrder(columnKey);
  }
};

const togglePin = async conversation => {
  const pinned = !conversation.pinned;
  conversation.pinned = pinned;
  rebuildColumns();
  try {
    await ConversationBoardAPI.pin({ conversationId: conversation.id, pinned });
  } catch {
    conversation.pinned = !pinned;
    rebuildColumns();
    useAlert(t('CONVERSATION_BOARD.ORDER.ERROR'));
  }
};

const openMoveDialog = conversation => moveDialogRef.value?.open(conversation);
const onMove = ({ conversation, agent }) => transfer(conversation, agent);

const openConversation = conversation =>
  conversationModalRef.value?.open(conversation.id);

// Reply, resolve or reassign inside the modal: bring the board up to date.
const onModalClose = () => fetchBoard();

const openFullConversation = conversationId => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: conversationId,
    },
  });
};

const timeAgo = seconds => shortTimestamp(dynamicTime(seconds));

// The TV mode runs full screen on a wall monitor; open it in its own tab.
const openTvMode = () => {
  const { href } = router.resolve({
    name: 'conversation_board_tv',
    params: { accountId: route.params.accountId },
  });
  window.open(href, '_blank', 'noopener');
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex flex-wrap items-center gap-3 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-lg font-medium text-n-slate-12 me-auto">
        {{ t('CONVERSATION_BOARD.TITLE') }}
      </h1>
      <input
        v-model="search"
        type="search"
        :placeholder="t('CONVERSATION_BOARD.SEARCH')"
        class="!mb-0 w-64 !h-8 !text-sm"
      />
      <select v-model="teamId" class="!mb-0 w-56 !h-8 !text-sm !py-0">
        <option value="">{{ t('CONVERSATION_BOARD.ALL_TEAMS') }}</option>
        <option v-for="team in teams" :key="team.id" :value="String(team.id)">
          {{ team.name }}
        </option>
      </select>
      <Button
        icon="i-lucide-monitor"
        size="sm"
        variant="faded"
        color="slate"
        :label="t('CONVERSATION_BOARD.TV.BUTTON')"
        @click="openTvMode"
      />
      <Button
        icon="i-lucide-refresh-cw"
        size="sm"
        variant="ghost"
        color="slate"
        :title="t('CONVERSATION_BOARD.REFRESH')"
        @click="fetchBoard"
      />
    </header>

    <p v-if="truncated" class="px-6 pt-2 text-xs text-n-slate-11">
      {{ t('CONVERSATION_BOARD.TRUNCATED', { count: conversations.length }) }}
    </p>

    <div
      v-if="isLoading"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ t('CONVERSATION_BOARD.LOADING') }}
    </div>
    <div
      v-else-if="hasError"
      class="flex items-center justify-center flex-1 text-sm text-n-ruby-11"
    >
      {{ t('CONVERSATION_BOARD.LOAD_ERROR') }}
    </div>

    <div v-else class="flex flex-1 gap-3 p-4 overflow-x-auto overflow-y-hidden">
      <div
        v-for="column in columns"
        :key="column.key"
        class="flex flex-col w-72 shrink-0 max-h-full rounded-xl bg-n-alpha-1 border"
        :class="column.isMine ? 'border-n-brand/40' : 'border-n-weak'"
      >
        <div class="flex items-center gap-2 px-3 py-2.5">
          <Avatar
            v-if="column.agent"
            :src="column.agent.thumbnail"
            :name="column.agent.name"
            :status="column.agent.availability_status"
            :size="24"
            rounded-full
          />
          <span
            v-else
            class="i-lucide-user-round-x size-5 text-n-slate-10 shrink-0"
          />
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{
              column.agent
                ? column.agent.name
                : t('CONVERSATION_BOARD.UNASSIGNED')
            }}
          </span>
          <span
            v-if="column.isMine"
            class="px-1.5 text-xs rounded-md bg-n-brand/10 text-n-blue-11 shrink-0"
          >
            {{ t('CONVERSATION_BOARD.MINE') }}
          </span>
          <span
            class="px-1.5 ms-auto text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
          >
            {{ (columnCards[column.key] || []).length }}
          </span>
        </div>

        <Draggable
          :list="columnCards[column.key] || []"
          group="conversation-board"
          item-key="id"
          :move="checkMove"
          :component-data="{ 'data-column': column.key }"
          ghost-class="opacity-40"
          class="flex flex-col flex-1 gap-2 px-2 pb-2 overflow-y-auto min-h-16"
          @start="isDragging = true"
          @end="isDragging = false"
          @change="event => onColumnChange(column.key, event)"
        >
          <template #item="{ element }">
            <button
              type="button"
              class="flex flex-col gap-1.5 p-3 text-start rounded-lg bg-n-solid-2 border hover:border-n-slate-7 cursor-grab active:cursor-grabbing"
              :class="element.pinned ? 'border-n-amber-8' : 'border-n-weak'"
              @click="openConversation(element)"
            >
              <div class="flex items-center w-full gap-2">
                <Avatar
                  :src="element.contact.thumbnail"
                  :name="element.contact.name || '?'"
                  :size="20"
                  rounded-full
                />
                <span
                  class="flex-1 min-w-0 text-sm font-medium truncate text-n-slate-12"
                >
                  {{ element.contact.name || element.contact.phone_number }}
                </span>
                <span class="text-xs text-n-slate-10 shrink-0">
                  {{ timeAgo(element.last_activity_at) }}
                </span>
                <Button
                  :icon="element.pinned ? 'i-lucide-pin-off' : 'i-lucide-pin'"
                  size="xs"
                  variant="ghost"
                  :color="element.pinned ? 'amber' : 'slate'"
                  :title="
                    element.pinned
                      ? t('CONVERSATION_BOARD.ORDER.UNPIN')
                      : t('CONVERSATION_BOARD.ORDER.PIN')
                  "
                  @click.stop="togglePin(element)"
                />
                <Button
                  icon="i-lucide-arrow-right-left"
                  size="xs"
                  variant="ghost"
                  color="slate"
                  :title="t('CONVERSATION_BOARD.MOVE.BUTTON')"
                  @click.stop="openMoveDialog(element)"
                />
              </div>
              <p
                v-if="element.last_message"
                class="w-full text-xs line-clamp-2 text-n-slate-11"
              >
                <span
                  v-if="!element.last_message.incoming"
                  class="i-lucide-reply size-3 inline-block align-middle me-0.5"
                />
                {{ element.last_message.content }}
              </p>
              <div class="flex flex-wrap items-center w-full gap-1">
                <span
                  class="px-1.5 text-xs rounded bg-n-alpha-2 text-n-slate-11 truncate max-w-40"
                >
                  {{ element.inbox_name }}
                </span>
                <span
                  v-if="element.status === 'pending'"
                  class="px-1.5 text-xs rounded bg-n-amber-3 text-n-amber-11"
                >
                  {{ t('CONVERSATION_BOARD.PENDING') }}
                </span>
                <span
                  v-if="element.waiting_since"
                  class="px-1.5 text-xs rounded bg-n-ruby-3 text-n-ruby-11"
                  :title="t('CONVERSATION_BOARD.WAITING')"
                >
                  {{ timeAgo(element.waiting_since) }}
                </span>
                <span
                  v-for="label in element.labels.slice(0, 3)"
                  :key="label"
                  class="px-1.5 text-xs rounded bg-n-blue-3 text-n-blue-11"
                >
                  {{ label }}
                </span>
              </div>
            </button>
          </template>
          <template #footer>
            <p
              v-if="!(columnCards[column.key] || []).length"
              class="py-4 text-xs text-center text-n-slate-10"
            >
              {{ t('CONVERSATION_BOARD.EMPTY_COLUMN') }}
            </p>
          </template>
        </Draggable>
      </div>
    </div>

    <MoveConversationDialog
      ref="moveDialogRef"
      :teams="teams"
      :directory="directory"
      :default-team-id="teamId"
      @move="onMove"
    />
    <ConversationModal
      ref="conversationModalRef"
      @close="onModalClose"
      @open-full="openFullConversation"
    />
  </section>
</template>
