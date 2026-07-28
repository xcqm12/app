import { LeftArrowIcon, RightArrowIcon } from "@modrinth/assets";
import type { StageConfigInput } from "@modrinth/ui";
import { markRaw } from "vue";

import type { ManageVersionContextValue } from "../manage-version-modal";
import AddEnvironmentStage from "~/components/ui/create-project-version/stages/AddEnvironmentStage.vue";

export const stageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "add-environment",
  stageContent: markRaw(AddEnvironmentStage),
  title: (ctx) => (ctx.editingVersion.value ? "编辑环境" : "环境"),
  // BBSMC: 始终显示环境步骤让用户确认/修改（即使已自动推断 / 已有值）
  // 仅在以下情况跳过：项目本身没有环境概念 / 汉化包 / 软件资源 / 编辑模式
  skip: (ctx) =>
    ctx.noEnvironmentProject.value ||
    ctx.isLanguageVersion.value ||
    ctx.draftVersion.value.type === "software" ||
    ctx.editingVersion.value,
  cannotNavigateForward: (ctx) => !ctx.draftVersion.value.environment,
  leftButtonConfig: (ctx) => ({
    label: "返回",
    icon: LeftArrowIcon,
    onClick: () => ctx.modal.value?.prevStage(),
  }),
  rightButtonConfig: (ctx) => ({
    label: ctx.getNextLabel(),
    icon: RightArrowIcon,
    iconPosition: "after",
    disabled: !ctx.draftVersion.value.environment,
    onClick: () => ctx.modal.value?.nextStage(),
  }),
};

export const fromDetailsStageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "from-details-environment",
  stageContent: markRaw(AddEnvironmentStage),
  title: "编辑环境",
  nonProgressStage: true,
  leftButtonConfig: (ctx) => ({
    label: "返回",
    icon: LeftArrowIcon,
    disabled: !ctx.draftVersion.value.environment,
    onClick: () => ctx.modal.value?.setStage("metadata"),
  }),
  rightButtonConfig: (ctx) => ctx.saveButtonConfig(),
};
