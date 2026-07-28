/**
 * Stage 配置注册中心
 *
 * 进度阶段顺序：
 *   资源类型 → 上传方式 → 上传内容 → 加载器 → 游戏版本 → 环境 → 依赖 → 确认信息 → 详情
 */
import { stageConfig as addFilesStageConfig } from "./add-files-stage.ts";
import {
  fromDetailsStageConfig as fromDetailsDependenciesStageConfig,
  stageConfig as dependenciesStageConfig,
} from "./dependencies-stage.ts";
import { stageConfig as detailsStageConfig } from "./details-stage.ts";
import {
  fromDetailsStageConfig as fromDetailsEnvironmentStageConfig,
  stageConfig as environmentStageConfig,
} from "./environment-stage.ts";
import {
  fromDetailsStageConfig as fromDetailsFilesStageConfig,
  stageConfig as filesUploadStageConfig,
} from "./files-upload-stage.ts";
import {
  fromDetailsStageConfig as fromDetailsLoadersStageConfig,
  stageConfig as loadersStageConfig,
} from "./loaders-stage.ts";
import {
  fromDetailsStageConfig as fromDetailsMcVersionsStageConfig,
  stageConfig as mcVersionsStageConfig,
} from "./mc-versions-stage.ts";
import { stageConfig as metadataStageConfig } from "./metadata-stage.ts";
import { stageConfig as uploadModeStageConfig } from "./upload-mode-stage.ts";

export const stageConfigs = [
  // 进度阶段
  addFilesStageConfig, // 1. 资源类型
  uploadModeStageConfig, // 2. 上传方式（含整合包确认）
  filesUploadStageConfig, // 3. 上传内容（文件 / 网盘）
  loadersStageConfig, // 4. 加载器
  mcVersionsStageConfig, // 5. 游戏版本
  environmentStageConfig, // 6. 环境
  dependenciesStageConfig, // 7. 依赖
  metadataStageConfig, // 8. 确认信息
  detailsStageConfig, // 9. 详情

  // 非进度阶段（编辑模式从 metadata 跳转用）
  fromDetailsFilesStageConfig,
  fromDetailsLoadersStageConfig,
  fromDetailsMcVersionsStageConfig,
  fromDetailsEnvironmentStageConfig,
  fromDetailsDependenciesStageConfig,
];
