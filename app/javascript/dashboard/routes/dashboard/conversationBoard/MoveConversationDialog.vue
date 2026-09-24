<script setup>
// Melck fork: move a board card to any team/agent without dragging across
// dozens of columns. Pick the team (sector) first, then the agent in it.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  teams: { type: Array, default: () => [] },
  directory: { type: Array, default: () => [] },
  defaultTeamId: { type: String, default: '' },
});

const emit = defineEmits(['move']);

const UNASSIGNED = 'unassigned';
const ALL_TEAMS = 'all';

const { t } = useI18n();
const dialogRef = ref(null);
const conversation = ref(null);
const teamId = ref(ALL_TEAMS);
const target = ref('');

const teamOptions = computed(() => [
  { value: ALL_TEAMS, label: t('CONVERSATION_BOARD.MOVE.ALL_TEAMS') },
  ...props.teams.map(team => ({ value: String(team.id), label: team.name })),
]);

const canReceive = agent =>
  agent.role === 'administrator' ||
  agent.inbox_ids.includes(conversation.value?.inbox_id);

const agentOptions = computed(() => {
  if (!conversation.value) return [];
  const team = props.teams.find(item => String(item.id) === teamId.value);
  const members = team
    ? props.directory.filter(agent => team.member_ids.includes(agent.id))
    : props.directory;
  const currentId = conversation.value.assignee_id;

  const options = members.map(agent => {
    let label = agent.name;
    if (agent.id === currentId) {
      label += ` ${t('CONVERSATION_BOARD.MOVE.CURRENT')}`;
    } else if (!canReceive(agent)) {
      label += ` ${t('CONVERSATION_BOARD.MOVE.NOT_MEMBER', {
        inbox: conversation.value.inbox_name,
      })}`;
    }
    return {
      value: String(agent.id),
      label,
      disabled: agent.id === currentId || !canReceive(agent),
    };
  });

  return [
    {
      value: UNASSIGNED,
      label: t('CONVERSATION_BOARD.UNASSIGNED'),
      disabled: !currentId,
    },
    ...options,
  ];
});

const teamOfAssignee = assigneeId => {
  const team = props.teams.find(item => item.member_ids.includes(assigneeId));
  return team ? String(team.id) : '';
};

const onTeamChange = value => {
  teamId.value = value;
  target.value = '';
};

const open = card => {
  conversation.value = card;
  teamId.value =
    props.defaultTeamId || teamOfAssignee(card.assignee_id) || ALL_TEAMS;
  target.value = '';
  dialogRef.value?.open();
};

const confirm = () => {
  if (!target.value) return;
  const agent =
    target.value === UNASSIGNED
      ? null
      : props.directory.find(item => String(item.id) === target.value);
  emit('move', { conversation: conversation.value, agent });
  dialogRef.value?.close();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="t('CONVERSATION_BOARD.MOVE.TITLE')"
    :description="
      conversation
        ? t('CONVERSATION_BOARD.MOVE.DESCRIPTION', {
            id: conversation.id,
            name:
              conversation.contact.name || conversation.contact.phone_number,
          })
        : ''
    "
    :confirm-button-label="t('CONVERSATION_BOARD.MOVE.CONFIRM')"
    :disable-confirm-button="!target"
    @confirm="confirm"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION_BOARD.MOVE.TEAM') }}
        </span>
        <Select
          :model-value="teamId"
          :options="teamOptions"
          class="[&>select]:w-full !w-full"
          @update:model-value="onTeamChange"
        />
      </label>
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION_BOARD.MOVE.AGENT') }}
        </span>
        <Select
          v-model="target"
          :options="agentOptions"
          :placeholder="t('CONVERSATION_BOARD.MOVE.SELECT_AGENT')"
          class="[&>select]:w-full !w-full"
        />
      </label>
    </div>
  </Dialog>
</template>
