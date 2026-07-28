import { LeftArrowIcon, RightArrowIcon } from "@modrinth/assets";
import type { StageConfigInput } from "@modrinth/ui";
import { markRaw } from "vue";

import type { ManageVersionContextValue } from "../manage-version-modal";
import AddMcVersionsStage from "~/components/ui/create-project-version/stages/AddMcVersionsStage.vue";

export const stageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "add-mc-versions",
  stageContent: markRaw(AddMcVersionsStage),
  title: (ctx) => (ctx.editingVersion.value ? "编辑游戏版本" : "游戏版本"),
  // BBSMC: 始终显示游戏版本步骤让用户确认/修改（即使已自动推断）
  // 仅在以下情况跳过：language 类型 / software 类型 / 编辑模式
  skip: (ctx) =>
    ctx.isLanguageVersion.value ||
    ctx.draftVersion.value.type === "software" ||
    ctx.editingVersion.value,
  cannotNavigateForward: (ctx) => ctx.draftVersion.value.game_versions.length === 0,
  leftButtonConfig: (ctx) => ({
    label: "返回",
    icon: LeftArrowIcon,
    onClick: () => ctx.modal.value?.prevStage(),
  }),
  rightButtonConfig: (ctx) => ({
    label: ctx.getNextLabel(),
    icon: RightArrowIcon,
    iconPosition: "after",
    disabled: ctx.draftVersion.value.game_versions.length === 0,
    onClick: () => ctx.modal.value?.nextStage(),
  }),
};

export const fromDetailsStageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "from-details-mc-versions",
  stageContent: markRaw(AddMcVersionsStage),
  title: "编辑游戏版本",
  nonProgressStage: true,
  leftButtonConfig: (ctx) => ({
    label: "返回",
    icon: LeftArrowIcon,
    disabled: ctx.draftVersion.value.game_versions.length === 0,
    onClick: () => ctx.modal.value?.setStage("metadata"),
  }),
  rightButtonConfig: (ctx) => ctx.saveButtonConfig(),
};
