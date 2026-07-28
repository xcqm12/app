import { LeftArrowIcon, RightArrowIcon } from "@modrinth/assets";
import type { StageConfigInput } from "@modrinth/ui";
import { markRaw } from "vue";

import type { ManageVersionContextValue } from "../manage-version-modal";
import AddDependenciesStage from "~/components/ui/create-project-version/stages/AddDependenciesStage.vue";

export const stageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "add-dependencies",
  stageContent: markRaw(AddDependenciesStage),
  title: (ctx) => (ctx.editingVersion.value ? "编辑依赖" : "依赖"),
  skip: (ctx) => ctx.noDependenciesProject.value, // modpack 跳过
  leftButtonConfig: (ctx) => ({
    label: "返回",
    icon: LeftArrowIcon,
    onClick: () => ctx.modal.value?.prevStage(),
  }),
  rightButtonConfig: (ctx) => ({
    label: ctx.getNextLabel(),
    icon: RightArrowIcon,
    iconPosition: "after",
    onClick: () => ctx.modal.value?.nextStage(),
  }),
};

export const fromDetailsStageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "from-details-dependencies",
  stageContent: markRaw(AddDependenciesStage),
  title: "编辑依赖",
  nonProgressStage: true,
  leftButtonConfig: (ctx) => ({
    label: "返回",
    icon: LeftArrowIcon,
    onClick: () => ctx.modal.value?.setStage("metadata"),
  }),
  rightButtonConfig: (ctx) => ctx.saveButtonConfig(),
};
