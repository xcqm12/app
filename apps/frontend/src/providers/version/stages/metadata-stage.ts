import { LeftArrowIcon, RightArrowIcon, XIcon } from "@modrinth/assets";
import type { StageConfigInput } from "@modrinth/ui";
import { markRaw } from "vue";

import type { ManageVersionContextValue } from "../manage-version-modal";
import MetadataStage from "~/components/ui/create-project-version/stages/MetadataStage.vue";

/**
 * 元数据汇总 stage（图1 第 5 步 "Metadata"）
 *
 * 创建模式：在最后一步显示所有已选信息的汇总，用户确认后跳到 details-stage 完成创建
 * 编辑模式：作为编辑入口，nonProgressStage=true，提供各 from-details-* 跳转
 */
export const stageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "metadata",
  stageContent: markRaw(MetadataStage),
  title: (ctx) => (ctx.editingVersion.value ? "编辑版本" : "确认信息"),
  nonProgressStage: (ctx) => ctx.editingVersion.value,
  leftButtonConfig: (ctx) =>
    ctx.editingVersion.value
      ? {
          label: "取消",
          icon: XIcon,
          onClick: () => ctx.modal.value?.hide(),
        }
      : {
          label: "返回",
          icon: LeftArrowIcon,
          onClick: () => ctx.modal.value?.prevStage(),
        },
  rightButtonConfig: (ctx) =>
    ctx.editingVersion.value
      ? {
          ...ctx.saveButtonConfig(),
        }
      : {
          label: ctx.getNextLabel(),
          icon: RightArrowIcon,
          iconPosition: "after",
          onClick: () => ctx.modal.value?.nextStage(),
        },
};
