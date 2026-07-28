<template>
  <div class="flex flex-col gap-2">
    <!-- 一级：仅限客户端 -->
    <button
      type="button"
      class="flex flex-col gap-1 rounded-xl border-2 border-solid p-4 text-left transition-all"
      :class="outerClass('client')"
      @click="setOuter('client')"
    >
      <div class="flex items-center gap-2 text-base font-semibold">
        仅限客户端
        <CheckCircleIcon v-if="outer === 'client'" class="ml-auto" />
      </div>
      <div class="text-xs" :class="outer === 'client' ? 'opacity-80' : 'text-secondary'">
        所有功能都在客户端完成，且与原版服务端兼容。
      </div>
    </button>

    <!-- 一级：仅限服务端 -->
    <button
      type="button"
      class="flex flex-col gap-1 rounded-xl border-2 border-solid p-4 text-left transition-all"
      :class="outerClass('server')"
      @click="setOuter('server')"
    >
      <div class="flex items-center gap-2 text-base font-semibold">
        仅限服务端
        <CheckCircleIcon v-if="outer === 'server'" class="ml-auto" />
      </div>
      <div class="text-xs" :class="outer === 'server' ? 'opacity-80' : 'text-secondary'">
        所有功能都在服务端完成，且与原版客户端兼容。
      </div>
    </button>

    <!-- 仅限服务端的子选项 -->
    <div v-if="outer === 'server'" class="ml-6 flex flex-col gap-2">
      <button
        type="button"
        class="rounded-lg border-2 border-solid p-3 text-left text-sm transition-all"
        :class="subClass('singleplayer')"
        @click="setSub('singleplayer')"
      >
        <div class="flex items-center gap-2 font-semibold">
          单人游戏也可工作
          <CheckCircleIcon v-if="sub === 'singleplayer'" class="ml-auto" />
        </div>
      </button>
      <button
        type="button"
        class="rounded-lg border-2 border-solid p-3 text-left text-sm transition-all"
        :class="subClass('dedicated')"
        @click="setSub('dedicated')"
      >
        <div class="flex items-center gap-2 font-semibold">
          仅限专用服务端
          <CheckCircleIcon v-if="sub === 'dedicated'" class="ml-auto" />
        </div>
      </button>
    </div>

    <!-- 一级：客户端和服务端 -->
    <button
      type="button"
      class="flex flex-col gap-1 rounded-xl border-2 border-solid p-4 text-left transition-all"
      :class="outerClass('client_and_server')"
      @click="setOuter('client_and_server')"
    >
      <div class="flex items-center gap-2 text-base font-semibold">
        客户端和服务端
        <CheckCircleIcon v-if="outer === 'client_and_server'" class="ml-auto" />
      </div>
      <div class="text-xs" :class="outer === 'client_and_server' ? 'opacity-80' : 'text-secondary'">
        在客户端和服务端均具备部分或全部功能。
      </div>
    </button>

    <!-- 客户端和服务端的子选项 -->
    <div v-if="outer === 'client_and_server'" class="ml-6 flex flex-col gap-2">
      <button
        type="button"
        class="rounded-lg border-2 border-solid p-3 text-left text-sm transition-all"
        :class="subClass('required_both')"
        @click="setSub('required_both')"
      >
        <div class="flex items-center gap-2 font-semibold">
          两者皆需
          <CheckCircleIcon v-if="sub === 'required_both'" class="ml-auto" />
        </div>
      </button>
      <button
        type="button"
        class="rounded-lg border-2 border-solid p-3 text-left text-sm transition-all"
        :class="subClass('optional_client')"
        @click="setSub('optional_client')"
      >
        <div class="flex items-center gap-2 font-semibold">
          客户端可选
          <CheckCircleIcon v-if="sub === 'optional_client'" class="ml-auto" />
        </div>
      </button>
      <button
        type="button"
        class="rounded-lg border-2 border-solid p-3 text-left text-sm transition-all"
        :class="subClass('optional_server')"
        @click="setSub('optional_server')"
      >
        <div class="flex items-center gap-2 font-semibold">
          服务端可选
          <CheckCircleIcon v-if="sub === 'optional_server'" class="ml-auto" />
        </div>
      </button>
      <button
        type="button"
        class="rounded-lg border-2 border-solid p-3 text-left text-sm transition-all"
        :class="subClass('optional_both_prefers_both')"
        @click="setSub('optional_both_prefers_both')"
      >
        <div class="flex items-center gap-2 font-semibold">
          两者可选，两端均安装效果最佳
          <CheckCircleIcon v-if="sub === 'optional_both_prefers_both'" class="ml-auto" />
        </div>
      </button>
      <button
        type="button"
        class="rounded-lg border-2 border-solid p-3 text-left text-sm transition-all"
        :class="subClass('optional_both')"
        @click="setSub('optional_both')"
      >
        <div class="flex items-center gap-2 font-semibold">
          两者可选，任一端安装效果相同
          <CheckCircleIcon v-if="sub === 'optional_both'" class="ml-auto" />
        </div>
      </button>
    </div>

    <!-- 一级：仅限单人游戏 -->
    <button
      type="button"
      class="flex flex-col gap-1 rounded-xl border-2 border-solid p-4 text-left transition-all"
      :class="outerClass('singleplayer')"
      @click="setOuter('singleplayer')"
    >
      <div class="flex items-center gap-2 text-base font-semibold">
        仅限单人游戏
        <CheckCircleIcon v-if="outer === 'singleplayer'" class="ml-auto" />
      </div>
      <div class="text-xs" :class="outer === 'singleplayer' ? 'opacity-80' : 'text-secondary'">
        仅在单人游戏或未连接多人游戏服务端时工作。
      </div>
    </button>
  </div>
</template>

<script setup lang="ts">
import { CheckCircleIcon } from "@modrinth/assets";
import { computed, ref, watch } from "vue";

type EnvironmentValue =
  | "client_only"
  | "server_only"
  | "singleplayer_only"
  | "dedicated_server_only"
  | "client_and_server"
  | "client_only_server_optional"
  | "server_only_client_optional"
  | "client_or_server"
  | "client_or_server_prefers_both"
  | "unknown";

type OuterKey = "client" | "server" | "client_and_server" | "singleplayer";
type SubKey =
  | "singleplayer"
  | "dedicated"
  | "required_both"
  | "optional_client"
  | "optional_server"
  | "optional_both"
  | "optional_both_prefers_both";

const value = defineModel<EnvironmentValue | undefined>({ required: false });

const outer = ref<OuterKey | undefined>();
const sub = ref<SubKey | undefined>();

// outer + sub → v3 Environment 枚举
const computedEnvironment = computed<EnvironmentValue | undefined>(() => {
  switch (outer.value) {
    case "client":
      return "client_only";
    case "server":
      if (sub.value === "singleplayer") return "server_only";
      if (sub.value === "dedicated") return "dedicated_server_only";
      return undefined;
    case "client_and_server":
      switch (sub.value) {
        case "required_both":
          return "client_and_server";
        case "optional_client":
          return "server_only_client_optional";
        case "optional_server":
          return "client_only_server_optional";
        case "optional_both_prefers_both":
          return "client_or_server_prefers_both";
        case "optional_both":
          return "client_or_server";
        default:
          return undefined;
      }
    case "singleplayer":
      return "singleplayer_only";
    default:
      return undefined;
  }
});

// 反向：v3 Environment → outer + sub
function loadFromValue(env: EnvironmentValue | undefined) {
  switch (env) {
    case "client_only":
      outer.value = "client";
      sub.value = undefined;
      break;
    case "server_only":
      outer.value = "server";
      sub.value = "singleplayer";
      break;
    case "dedicated_server_only":
      outer.value = "server";
      sub.value = "dedicated";
      break;
    case "singleplayer_only":
      outer.value = "singleplayer";
      sub.value = undefined;
      break;
    case "client_and_server":
      outer.value = "client_and_server";
      sub.value = "required_both";
      break;
    case "server_only_client_optional":
      outer.value = "client_and_server";
      sub.value = "optional_client";
      break;
    case "client_only_server_optional":
      outer.value = "client_and_server";
      sub.value = "optional_server";
      break;
    case "client_or_server_prefers_both":
      outer.value = "client_and_server";
      sub.value = "optional_both_prefers_both";
      break;
    case "client_or_server":
      outer.value = "client_and_server";
      sub.value = "optional_both";
      break;
    default:
      outer.value = undefined;
      sub.value = undefined;
  }
}

// 同步：本地状态 → v-model
watch(computedEnvironment, (env) => {
  if (env !== value.value) value.value = env;
});

// 同步：v-model → 本地状态（编辑模式回填）
watch(
  () => value.value,
  (env) => loadFromValue(env),
  { immediate: true },
);

function setOuter(key: OuterKey) {
  outer.value = key;
  // 切换大类时若有子选项，默认选第一个；client/singleplayer 无子选项则清空
  if (key === "server") {
    sub.value = "singleplayer";
  } else if (key === "client_and_server") {
    sub.value = "required_both";
  } else {
    sub.value = undefined;
  }
}

function setSub(key: SubKey) {
  sub.value = key;
}

function outerClass(key: OuterKey) {
  return outer.value === key
    ? "border-brand bg-highlight-green text-brand"
    : "border-surface-5 bg-button-bg text-contrast hover:bg-button-bg-hover";
}

function subClass(key: SubKey) {
  return sub.value === key
    ? "border-brand bg-highlight-green text-brand"
    : "border-surface-5 bg-button-bg text-contrast hover:bg-button-bg-hover";
}
</script>
