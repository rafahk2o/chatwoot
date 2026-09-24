<script setup>
// Melck fork: full-screen operations panel for a wall monitor. Read-only
// numbers per team and agent (load, conversations waiting for a reply and the
// longest wait), plus alerts. No customer names or messages are shown.
//
// Thresholds come from the URL so each screen can be tuned without a deploy:
//   ?warn=15&alert=30&capacity=40&rotate=0
// warn/alert are minutes waiting for a reply, capacity is conversations per
// agent, rotate > 0 shows one team at a time for that many seconds.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { emitter } from 'shared/helpers/mitt';
import ConversationBoardAPI from 'dashboard/api/conversationBoard';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const POLL_INTERVAL = 30000;
const CLOCK_INTERVAL = 15000;

const { t } = useI18n();
const route = useRoute();

const numberParam = (name, fallback) => {
  const value = Number(route.query[name]);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
};
const WARN_MINUTES = numberParam('warn', 15);
const ALERT_MINUTES = numberParam('alert', 30);
const CAPACITY = numberParam('capacity', 40);
const ROTATE_SECONDS = numberParam('rotate', 0);

const teams = ref([]);
const directory = ref([]);
const conversations = ref([]);
const hasError = ref(false);
const lastUpdated = ref(null);
const now = ref(Date.now() / 1000);
const pageIndex = ref(0);

const waitMinutes = conversation =>
  conversation.waiting_since
    ? Math.max(0, (now.value - conversation.waiting_since) / 60)
    : null;

const formatMinutes = minutes => {
  if (minutes === null || minutes === undefined) return '—';
  const total = Math.floor(minutes);
  if (total < 60) return `${total} min`;
  return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, '0')}`;
};

const waitLevel = minutes => {
  if (minutes === null || minutes === undefined) return 'ok';
  if (minutes >= ALERT_MINUTES) return 'alert';
  if (minutes >= WARN_MINUTES) return 'warn';
  return 'ok';
};

const summarize = list => {
  const waits = list.map(waitMinutes).filter(minutes => minutes !== null);
  return {
    total: list.length,
    waiting: waits.length,
    late: waits.filter(minutes => minutes >= ALERT_MINUTES).length,
    longestWait: waits.length ? Math.max(...waits) : null,
  };
};

const statsByAgent = computed(() => {
  const grouped = {};
  conversations.value.forEach(conversation => {
    const key = conversation.assignee_id || 'unassigned';
    (grouped[key] ||= []).push(conversation);
  });
  return Object.fromEntries(
    Object.entries(grouped).map(([key, list]) => [key, summarize(list)])
  );
});

const emptyStats = { total: 0, waiting: 0, late: 0, longestWait: null };
const agentStats = agentId => statsByAgent.value[agentId] || emptyStats;

const overview = computed(() => ({
  ...summarize(conversations.value),
  open: conversations.value.filter(c => c.status === 'open').length,
  pending: conversations.value.filter(c => c.status === 'pending').length,
  unassigned: agentStats('unassigned'),
}));

const agentRow = agent => ({ ...agent, stats: agentStats(agent.id) });
const byLoad = (a, b) =>
  b.stats.waiting - a.stats.waiting || b.stats.total - a.stats.total;

const blocks = computed(() => {
  const inTeam = new Set(teams.value.flatMap(team => team.member_ids));
  const teamBlocks = teams.value.map(team => ({
    key: `team-${team.id}`,
    name: team.name,
    agents: directory.value
      .filter(agent => team.member_ids.includes(agent.id))
      .map(agentRow)
      .sort(byLoad),
  }));
  const withoutTeam = directory.value
    .filter(agent => !inTeam.has(agent.id) && agentStats(agent.id).total)
    .map(agentRow)
    .sort(byLoad);
  if (withoutTeam.length) {
    teamBlocks.push({
      key: 'no-team',
      name: t('CONVERSATION_BOARD.TV.NO_TEAM'),
      agents: withoutTeam,
    });
  }
  return teamBlocks
    .filter(block => block.agents.length)
    .map(block => ({
      ...block,
      stats: block.agents.reduce(
        (sum, agent) => ({
          total: sum.total + agent.stats.total,
          waiting: sum.waiting + agent.stats.waiting,
          late: sum.late + agent.stats.late,
        }),
        { total: 0, waiting: 0, late: 0 }
      ),
    }));
});

const visibleBlocks = computed(() => {
  if (!ROTATE_SECONDS || !blocks.value.length) return blocks.value;
  return [blocks.value[pageIndex.value % blocks.value.length]];
});

const alerts = computed(() => {
  const list = [];
  const { unassigned } = overview.value;
  if (unassigned.total) {
    list.push({
      key: 'unassigned',
      level: waitLevel(unassigned.longestWait),
      text: t('CONVERSATION_BOARD.TV.ALERT_UNASSIGNED', {
        count: unassigned.total,
        time: formatMinutes(unassigned.longestWait),
      }),
    });
  }
  blocks.value
    .filter(block => block.stats.late)
    .forEach(block => {
      list.push({
        key: `late-${block.key}`,
        level: 'alert',
        text: t('CONVERSATION_BOARD.TV.ALERT_WAIT', {
          team: block.name,
          count: block.stats.late,
          minutes: ALERT_MINUTES,
        }),
      });
    });
  directory.value
    .filter(agent => agentStats(agent.id).total > CAPACITY)
    .sort((a, b) => agentStats(b.id).total - agentStats(a.id).total)
    .forEach(agent => {
      list.push({
        key: `capacity-${agent.id}`,
        level: 'alert',
        text: t('CONVERSATION_BOARD.TV.ALERT_CAPACITY', {
          name: agent.name,
          count: agentStats(agent.id).total,
          limit: CAPACITY,
        }),
      });
    });
  return list;
});

const loadPercent = total => Math.min(100, (total / (CAPACITY || 1)) * 100);
const loadLevel = total => {
  if (total > CAPACITY) return 'alert';
  if (total > CAPACITY * 0.75) return 'warn';
  return 'ok';
};

const LEVEL_TEXT = {
  ok: 'text-n-slate-12',
  warn: 'text-n-amber-11',
  alert: 'text-n-ruby-11',
};
const LEVEL_BAR = {
  ok: 'bg-n-teal-9',
  warn: 'bg-n-amber-9',
  alert: 'bg-n-ruby-9',
};
const LEVEL_ALERT = {
  ok: 'border-n-weak',
  warn: 'border-n-amber-8 bg-n-amber-3',
  alert: 'border-n-ruby-8 bg-n-ruby-3 animate-pulse',
};

const clock = computed(() =>
  new Date(now.value * 1000).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  })
);

const fetchBoard = async () => {
  try {
    const { data } = await ConversationBoardAPI.get();
    teams.value = data.teams;
    directory.value = data.directory;
    conversations.value = data.conversations;
    hasError.value = false;
    lastUpdated.value = new Date();
  } catch {
    hasError.value = true;
  }
};
const scheduleRefresh = debounce(fetchBoard, 1500);

// Keep the monitor awake while the panel is open.
let wakeLock = null;
const requestWakeLock = async () => {
  try {
    wakeLock = await navigator.wakeLock?.request('screen');
  } catch {
    wakeLock = null;
  }
};
const onVisibilityChange = () => {
  if (document.visibilityState === 'visible') {
    requestWakeLock();
    fetchBoard();
  }
};

const toggleFullscreen = () => {
  if (document.fullscreenElement) {
    document.exitFullscreen?.();
  } else {
    document.documentElement.requestFullscreen?.();
  }
};

const timers = [];
onMounted(() => {
  fetchBoard();
  requestWakeLock();
  emitter.on('fetch_conversation_stats', scheduleRefresh);
  document.addEventListener('visibilitychange', onVisibilityChange);
  timers.push(setInterval(fetchBoard, POLL_INTERVAL));
  timers.push(
    setInterval(() => {
      now.value = Date.now() / 1000;
    }, CLOCK_INTERVAL)
  );
  if (ROTATE_SECONDS) {
    timers.push(
      setInterval(() => {
        pageIndex.value += 1;
      }, ROTATE_SECONDS * 1000)
    );
  }
});
onBeforeUnmount(() => {
  emitter.off('fetch_conversation_stats', scheduleRefresh);
  document.removeEventListener('visibilitychange', onVisibilityChange);
  timers.forEach(clearInterval);
  wakeLock?.release?.();
});
</script>

<template>
  <div class="dark">
    <main
      class="flex flex-col w-screen h-screen gap-5 p-6 overflow-hidden bg-n-background text-n-slate-12"
    >
      <header class="flex items-center gap-6">
        <h1 class="text-3xl font-semibold me-auto">
          {{ t('CONVERSATION_BOARD.TV.TITLE') }}
        </h1>
        <span v-if="hasError" class="text-lg text-n-ruby-11">
          {{ t('CONVERSATION_BOARD.TV.OFFLINE') }}
        </span>
        <span v-else-if="lastUpdated" class="text-sm text-n-slate-10">
          {{
            t('CONVERSATION_BOARD.TV.UPDATED', {
              time: lastUpdated.toLocaleTimeString(),
            })
          }}
        </span>
        <span class="text-4xl font-semibold tabular-nums">{{ clock }}</span>
        <button
          type="button"
          class="p-2 rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          :title="t('CONVERSATION_BOARD.TV.FULLSCREEN')"
          @click="toggleFullscreen"
        >
          <span class="block i-lucide-maximize size-6" />
        </button>
      </header>

      <section class="grid grid-cols-5 gap-4">
        <div class="p-4 rounded-xl bg-n-alpha-1 border border-n-weak">
          <p class="text-base text-n-slate-11">
            {{ t('CONVERSATION_BOARD.TV.OPEN') }}
          </p>
          <p class="text-5xl font-semibold tabular-nums">{{ overview.open }}</p>
        </div>
        <div class="p-4 rounded-xl bg-n-alpha-1 border border-n-weak">
          <p class="text-base text-n-slate-11">
            {{ t('CONVERSATION_BOARD.TV.PENDING') }}
          </p>
          <p class="text-5xl font-semibold tabular-nums">
            {{ overview.pending }}
          </p>
        </div>
        <div class="p-4 rounded-xl bg-n-alpha-1 border border-n-weak">
          <p class="text-base text-n-slate-11">
            {{ t('CONVERSATION_BOARD.TV.WAITING') }}
          </p>
          <p class="text-5xl font-semibold tabular-nums">
            {{ overview.waiting }}
          </p>
        </div>
        <div class="p-4 rounded-xl bg-n-alpha-1 border border-n-weak">
          <p class="text-base text-n-slate-11">
            {{ t('CONVERSATION_BOARD.TV.LONGEST_WAIT') }}
          </p>
          <p
            class="text-5xl font-semibold tabular-nums"
            :class="LEVEL_TEXT[waitLevel(overview.longestWait)]"
          >
            {{ formatMinutes(overview.longestWait) }}
          </p>
        </div>
        <div class="p-4 rounded-xl bg-n-alpha-1 border border-n-weak">
          <p class="text-base text-n-slate-11">
            {{ t('CONVERSATION_BOARD.TV.UNASSIGNED') }}
          </p>
          <p
            class="text-5xl font-semibold tabular-nums"
            :class="
              overview.unassigned.total
                ? LEVEL_TEXT[waitLevel(overview.unassigned.longestWait)]
                : ''
            "
          >
            {{ overview.unassigned.total }}
          </p>
        </div>
      </section>

      <div class="flex flex-1 min-h-0 gap-5">
        <section
          class="grid content-start flex-1 min-h-0 gap-4 overflow-hidden"
          :class="
            ROTATE_SECONDS
              ? 'grid-cols-1'
              : 'grid-cols-[repeat(auto-fill,minmax(22rem,1fr))]'
          "
        >
          <article
            v-for="block in visibleBlocks"
            :key="block.key"
            class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1 border border-n-weak"
          >
            <header class="flex items-baseline gap-3">
              <h2 class="text-xl font-semibold capitalize me-auto">
                {{ block.name }}
              </h2>
              <span class="text-base text-n-slate-11 tabular-nums">
                {{
                  t('CONVERSATION_BOARD.TV.TEAM_SUMMARY', {
                    total: block.stats.total,
                    waiting: block.stats.waiting,
                  })
                }}
              </span>
            </header>
            <ul class="flex flex-col gap-2.5">
              <li
                v-for="agent in block.agents"
                :key="agent.id"
                class="flex items-center gap-3"
              >
                <Avatar
                  :src="agent.thumbnail"
                  :name="agent.name"
                  :status="agent.availability_status"
                  :size="32"
                  rounded-full
                />
                <div class="flex flex-col flex-1 min-w-0 gap-1">
                  <div class="flex items-baseline gap-2">
                    <span class="text-base truncate me-auto">
                      {{ agent.name }}
                    </span>
                    <span
                      class="text-lg font-semibold tabular-nums"
                      :class="LEVEL_TEXT[loadLevel(agent.stats.total)]"
                    >
                      {{ agent.stats.total }}
                    </span>
                  </div>
                  <div class="h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
                    <div
                      class="h-full rounded-full"
                      :class="LEVEL_BAR[loadLevel(agent.stats.total)]"
                      :style="{ width: `${loadPercent(agent.stats.total)}%` }"
                    />
                  </div>
                </div>
                <span
                  class="w-28 text-sm text-end tabular-nums"
                  :class="LEVEL_TEXT[waitLevel(agent.stats.longestWait)]"
                >
                  <template v-if="agent.stats.waiting">
                    {{
                      t('CONVERSATION_BOARD.TV.AGENT_WAITING', {
                        count: agent.stats.waiting,
                        time: formatMinutes(agent.stats.longestWait),
                      })
                    }}
                  </template>
                </span>
              </li>
            </ul>
          </article>
        </section>

        <aside class="flex flex-col w-96 shrink-0 gap-3 min-h-0">
          <h2 class="text-xl font-semibold">
            {{ t('CONVERSATION_BOARD.TV.ALERTS') }}
          </h2>
          <p
            v-if="!alerts.length"
            class="p-4 text-lg rounded-xl border border-n-teal-8 bg-n-teal-3 text-n-teal-11"
          >
            {{ t('CONVERSATION_BOARD.TV.NO_ALERTS') }}
          </p>
          <ul v-else class="flex flex-col gap-2 overflow-hidden">
            <li
              v-for="alert in alerts"
              :key="alert.key"
              class="p-3 text-base rounded-xl border"
              :class="LEVEL_ALERT[alert.level]"
            >
              {{ alert.text }}
            </li>
          </ul>
        </aside>
      </div>
    </main>
  </div>
</template>
