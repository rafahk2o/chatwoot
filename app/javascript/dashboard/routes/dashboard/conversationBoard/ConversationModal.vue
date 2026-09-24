<script setup>
// Melck fork: opens a board card's conversation in a modal, without leaving
// the board. It embeds the regular ConversationBox (messages, reply box,
// resolve/snooze, more actions) and the contact sidebar, the same way the
// notifications Inbox does, so everything works as in the conversation view.
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const emit = defineEmits(['close', 'openFull']);

const { t } = useI18n();
const store = useStore();
const { uiSettings } = useUISettings();

const currentChat = useMapGetter('getSelectedChat');
const conversationById = useMapGetter('getConversationById');

const conversationId = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
let agentsLoaded = false;

const isOpen = computed(() => conversationId.value !== null);
const isContactPanelOpen = computed(
  () => !!currentChat.value.id && uiSettings.value.is_contact_sidebar_open
);

const open = async id => {
  conversationId.value = id;
  hasError.value = false;
  isLoading.value = true;
  store.dispatch('clearSelectedState');
  if (!agentsLoaded) {
    agentsLoaded = true;
    store.dispatch('agents/get');
  }
  try {
    // Always refetch: the board data may be up to a minute old.
    await store.dispatch('getConversation', id);
    const conversation = conversationById.value(id);
    if (!conversation || conversationId.value !== id) {
      hasError.value = !conversation;
      return;
    }
    await store.dispatch('setActiveChat', { data: conversation });
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const close = () => {
  if (!isOpen.value) return;
  conversationId.value = null;
  store.dispatch('clearSelectedState');
  emit('close');
};

const openFull = () => {
  const id = conversationId.value;
  conversationId.value = null;
  emit('openFull', id);
};

// Keep the page from scrolling behind the modal.
watch(isOpen, value => {
  document.body.style.overflow = value ? 'hidden' : '';
});
onBeforeUnmount(() => {
  document.body.style.overflow = '';
  if (isOpen.value) store.dispatch('clearSelectedState');
});

defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-50 flex items-center justify-center p-2 md:p-6 bg-n-alpha-black1 backdrop-blur-[2px]"
      @mousedown.self="close"
    >
      <div
        class="relative flex flex-col w-full h-full max-w-7xl overflow-hidden border shadow-xl rounded-xl bg-n-surface-1 border-n-weak"
        role="dialog"
        aria-modal="true"
      >
        <div
          class="flex items-center justify-end gap-1 px-2 py-1 border-b border-n-weak shrink-0"
        >
          <span class="text-xs text-n-slate-11 me-auto ps-2">
            {{ t('CONVERSATION_BOARD.MODAL.TITLE', { id: conversationId }) }}
          </span>
          <Button
            icon="i-lucide-external-link"
            size="xs"
            variant="ghost"
            color="slate"
            :title="t('CONVERSATION_BOARD.MODAL.OPEN_FULL')"
            @click="openFull"
          />
          <Button
            icon="i-lucide-x"
            size="xs"
            variant="ghost"
            color="slate"
            :title="t('CONVERSATION_BOARD.MODAL.CLOSE')"
            @click="close"
          />
        </div>

        <div
          v-if="isLoading"
          class="flex items-center justify-center flex-1 bg-n-solid-1"
        >
          <Spinner class="text-n-brand" />
        </div>
        <div
          v-else-if="hasError || !currentChat.id"
          class="flex items-center justify-center flex-1 text-sm text-n-ruby-11"
        >
          {{ t('CONVERSATION_BOARD.MODAL.LOAD_ERROR') }}
        </div>
        <div v-else class="flex flex-1 min-h-0 min-w-0">
          <ConversationBox
            class="flex-1 [&.conversation-details-wrap]:!border-0"
            is-inbox-view
            :inbox-id="currentChat.inbox_id"
            :is-on-expanded-layout="false"
          >
            <SidepanelSwitch />
          </ConversationBox>
          <ConversationSidebar
            v-if="isContactPanelOpen"
            :current-chat="currentChat"
          />
        </div>
      </div>
    </div>
  </TeleportWithDirection>
</template>
