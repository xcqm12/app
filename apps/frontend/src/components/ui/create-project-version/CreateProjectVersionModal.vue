<template>
  <MultiStageModal
    ref="modal"
    :stages="ctx.stageConfigs"
    :context="ctx"
    :breadcrumbs="!editingVersion"
  />
</template>

<script setup lang="ts">
import type { Labrinth } from "@modrinth/api-client";
import {
  injectModrinthClient,
  injectNotificationManager,
  injectProjectPageContext,
  MultiStageModal,
} from "@modrinth/ui";
import type { ComponentExposed } from "vue-component-type-helpers";

import {
  createManageVersionContext,
  provideManageVersionContext,
} from "~/providers/version/manage-version-modal";

const emit = defineEmits<{
  (e: "save"): void;
}>();

const modal = useTemplateRef<ComponentExposed<typeof MultiStageModal>>("modal");

const ctx = createManageVersionContext(modal, () => emit("save"));
provideManageVersionContext(ctx);

const { newDraftVersion, editingVersion, handleNewFiles } = ctx;

const { projectV2 } = injectProjectPageContext();
const { addNotification } = injectNotificationManager();
const { labrinth } = injectModrinthClient();

async function openEditVersionModal(versionId: string, projectId: string, stageId?: string | null) {
  try {
    const versionData = await labrinth.versions_v3.getVersion(versionId);

    // BBSMC: 从已有 disk_urls 反推 5 个 input 临时字段，让 FilesUploadStage 能直接展示编辑
    const diskByPlatform = (versionData.disk_urls ?? []).reduce(
      (acc, d) => {
        if (d?.platform && d?.url) acc[d.platform] = d.url;
        return acc;
      },
      {} as Record<string, string>,
    );

    const draftVersionData: Labrinth.Versions.v3.DraftVersion = {
      project_id: projectId,
      version_id: versionId,
      name: versionData.name ?? "",
      version_number: versionData.version_number ?? "",
      changelog: versionData.changelog ?? "",
      game_versions: versionData.game_versions ?? [],
      version_type: versionData.version_type ?? "release",
      loaders: versionData.loaders ?? [],
      dependencies: versionData.dependencies ?? [],
      existing_files: versionData.files ?? [],
      environment: versionData.environment,
      featured: versionData.featured ?? false,
      // BBSMC 自定义字段（必须传入，否则编辑模式下显示"未选择"且字段丢失）
      type: versionData.type ?? null,
      disk_only: versionData.disk_only ?? false,
      disk_urls: versionData.disk_urls ?? [],
      version_links: versionData.version_links ?? [],
      is_modpack: versionData.is_modpack,
      quark_disk: diskByPlatform.quark ?? "",
      xunlei_disk: diskByPlatform.xunlei ?? "",
      baidu_disk: diskByPlatform.baidu ?? "",
      modrinth: diskByPlatform.modrinth ?? "",
      curseforge: diskByPlatform.curseforge ?? "",
    };

    if (projectV2.value.project_type === "modpack" && draftVersionData.loaders.includes("mrpack")) {
      draftVersionData.loaders.push(...(versionData.mrpack_loaders ?? []));
    }

    openCreateVersionModal(draftVersionData, stageId);
  } catch (err: any) {
    addNotification({
      title: "An error occurred",
      text: err.data ? err.data.description : err,
      type: "error",
    });
  }
}

function openCreateVersionModal(
  version: Labrinth.Versions.v3.DraftVersion | null = null,
  stageId: string | null = null,
) {
  newDraftVersion(projectV2.value.id, version);
  modal.value?.setStage(stageId ?? 0);
  modal.value?.show();
}

/**
 * 从外部（如 versions.vue 的 DropArea / FileInput）传入文件直接打开新建版本 modal。
 * 用户可在 modal 内继续添加文件 / 网盘 / 翻译链接。
 */
async function handleDropFiles(files: File[]) {
  newDraftVersion(projectV2.value.id, null);
  modal.value?.setStage(0);
  await handleNewFiles(files);
  modal.value?.show();
}

defineExpose({
  openEditVersionModal,
  openCreateVersionModal,
  handleDropFiles,
});
</script>
