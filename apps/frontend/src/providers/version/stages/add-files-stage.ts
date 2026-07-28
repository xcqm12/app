import { RightArrowIcon, XIcon } from "@modrinth/assets";
import type { StageConfigInput } from "@modrinth/ui";
import { markRaw } from "vue";

import type { ManageVersionContextValue } from "../manage-version-modal";
import AddFilesStage from "~/components/ui/create-project-version/stages/AddFilesStage.vue";

/**
 * 资源类型选择 stage（创建模式 modal 第一步）。
 * 编辑模式不会走这一步——版本已存在确定 type，编辑模式从 metadata 入口直接跳到对应的 from-details-* stage。
 */
export const stageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "add-files",
  stageContent: markRaw(AddFilesStage),
  title: () => "资源类型",
  cannotNavigateForward: (ctx) => !ctx.draftVersion.value.type,
  leftButtonConfig: (ctx) => ({
    label: "取消",
    icon: XIcon,
    onClick: () => ctx.modal.value?.hide(),
  }),
  rightButtonConfig: (ctx) => ({
    label: ctx.getNextLabel(),
    icon: RightArrowIcon,
    iconPosition: "after",
    disabled: !ctx.draftVersion.value.type,
    onClick: () => ctx.modal.value?.nextStage(),
  }),
};
