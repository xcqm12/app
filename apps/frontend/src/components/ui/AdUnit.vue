<template>
  <div v-if="mounted" class="ad-unit" :class="[`ad-unit--${format}`]">
    <ins
      class="adsbygoogle"
      :style="adStyle"
      data-ad-client="ca-pub-2727958509575372"
      :data-ad-slot="slot"
      :data-ad-format="format"
      :data-full-width-responsive="fullWidthResponsive"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, nextTick } from "vue";

const props = withDefaults(
  defineProps<{
    slot: string;
    format?: "auto" | "fluid" | "rectangle" | "horizontal" | "vertical";
    fullWidthResponsive?: string;
  }>(),
  {
    format: "auto",
    fullWidthResponsive: "true",
  },
);

const mounted = ref(false);

const adStyle = computed(() => {
  return "display:block";
});

onMounted(async () => {
  mounted.value = true;
  await nextTick();
  try {
    ((window as any).adsbygoogle = (window as any).adsbygoogle || []).push({});
  } catch {
    // AdSense not loaded (ad blocker, etc.)
  }
});
</script>

<style scoped lang="scss">
.ad-unit {
  width: 100%;
  overflow: hidden;
  min-height: 50px;

  &:empty {
    display: none;
  }
}
</style>
