<template>
  <EnvironmentSelectorV3 v-model="draftVersion.environment" />
</template>

<script lang="ts" setup>
import { injectManageVersionContext } from "~/providers/version/manage-version-modal";

import EnvironmentSelectorV3 from "../components/EnvironmentSelectorV3.vue";

const { draftVersion } = injectManageVersionContext();
</script>
