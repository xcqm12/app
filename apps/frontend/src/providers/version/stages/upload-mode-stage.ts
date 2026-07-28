import { LeftArrowIcon, RightArrowIcon, XIcon } from "@modrinth/assets";
import type { StageConfigInput } from "@modrinth/ui";
import { markRaw } from "vue";

import type { ManageVersionContextValue } from "../manage-version-modal";
import UploadModeStage from "~/components/ui/create-project-version/stages/UploadModeStage.vue";

/**
 * 是否满足"可以下一步"的条件：
 * 1. 必须选了 uploadMode
 * 2. 网盘模式（disk / both）+ Minecraft 类型下必须明确回答整合包问题
 *    （软件资源 / 汉化包不需要回答整合包）
 */
function canProceed(ctx: ManageVersionContextValue): boolean {
  if (!ctx.uploadMode.value) return false;
  const isMinecraftType = ctx.draftVersion.value.type === "minecraft";
  if (
    ctx.needsDiskInputs.value &&
    isMinecraftType &&
    typeof ctx.draftVersion.value.is_modpack !== "boolean"
  ) {
    return false;
  }
  return true;
}

export const stageConfig: StageConfigInput<ManageVersionContextValue> = {
  id: "upload-mode",
  stageContent: markRaw(UploadModeStage),
  title: (ctx) => (ctx.editingVersion.value ? "上传方式" : "上传方式"),
  cannotNavigateForward: (ctx) => !canProceed(ctx),
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
  rightButtonConfig: (ctx) => ({
    label: ctx.getNextLabel(),
    icon: RightArrowIcon,
    iconPosition: "after",
    disabled: !canProceed(ctx),
    onClick: () => ctx.modal.value?.nextStage(),
  }),
};
