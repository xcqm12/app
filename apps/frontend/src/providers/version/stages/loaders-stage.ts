import { LeftArrowIcon, RightArrowIcon } from "@modrinth/assets";
import type { StageConfigInput } from "@modrinth/ui";
import { markRaw } from "vue";

import type { ManageVersionContextValue } from "../manage-version-modal";
import AddLoadersStage from "~/components/ui/create-project-version/stages/AddLoadersStage.vue";

export const stageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "add-loaders",
  stageContent: markRaw(AddLoadersStage),
  title: (ctx) => (ctx.editingVersion.value ? "编辑加载器" : "加载器"),
  // BBSMC: 始终显示加载器步骤让用户确认/修改
  // - 资源包/数据包项目：跳过（loader 由 project_type 锁定为 minecraft/datapack）
  // - 整合包（modpack）：保留显示，AddLoadersStage 内部会把绑定切到 mrpack_loaders
  //   让用户确认整合包内部使用的加载器（forge/fabric/...）
  // - 汉化包 / 编辑模式：跳过
  skip: (ctx) => {
    if (ctx.isLanguageVersion.value || ctx.editingVersion.value) return true;
    const isModpack = ctx.projectType.value === "modpack";
    return ctx.noLoadersProject.value && !isModpack;
  },
  cannotNavigateForward: (ctx) => ctx.draftVersion.value.loaders.length === 0,
  leftButtonConfig: (ctx) => ({
    label: "返回",
    icon: LeftArrowIcon,
    onClick: () => ctx.modal.value?.prevStage(),
  }),
  rightButtonConfig: (ctx) => ({
    label: ctx.getNextLabel(),
    icon: RightArrowIcon,
    iconPosition: "after",
    disabled: ctx.draftVersion.value.loaders.length === 0,
    onClick: () => ctx.modal.value?.nextStage(),
  }),
};

export const fromDetailsStageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "from-details-loaders",
  stageContent: markRaw(AddLoadersStage),
  title: "编辑加载器",
  nonProgressStage: true,
  leftButtonConfig: (ctx) => ({
    label: "返回",
    icon: LeftArrowIcon,
    disabled: ctx.draftVersion.value.loaders.length === 0,
    onClick: () => ctx.modal.value?.setStage("metadata"),
  }),
  rightButtonConfig: (ctx) => ctx.saveButtonConfig(),
};
