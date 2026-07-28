/**
 * v3 Environment 文案表
 *
 * 翻译参考上游 packages/ui/src/components/project/settings/environment/environments.ts
 * 本地不使用 i18n MessageDescriptor，直接用中文字符串以避免引入 useVIntl 依赖。
 *
 * 用于 MetadataStage 等汇总展示场景。如果未来需要 i18n，可改造成 useVIntl + defineMessage。
 *
 * 注：Environment 类型本应来自 @modrinth/api-client 的 Labrinth.Projects.v3.Environment，
 * 但 packages/ui 中 namespace 解析有差异，故内联定义以避免类型解析问题。
 * 9 项枚举与 v3 Environment 完全一致，由后端 loader_field 'environment' 注册。
 */
export type EnvironmentValue =
  | 'client_only'
  | 'server_only'
  | 'singleplayer_only'
  | 'dedicated_server_only'
  | 'client_and_server'
  | 'client_only_server_optional'
  | 'server_only_client_optional'
  | 'client_or_server'
  | 'client_or_server_prefers_both'
  | 'unknown'

export const ENVIRONMENTS_COPY: Record<
  EnvironmentValue,
  {
    title: string
    description: string
  }
> = {
  client_only: {
    title: '仅限客户端',
    description: '所有功能都在客户端完成，且与原版服务端兼容。',
  },
  server_only: {
    title: '仅限服务端，单人游戏也可工作',
    description: '所有功能都在服务端完成，且与原版客户端兼容。在单人游戏的内部服务端中也可工作。',
  },
  singleplayer_only: {
    title: '仅限单人游戏',
    description: '仅在单人游戏或未连接多人游戏服务端时工作。',
  },
  dedicated_server_only: {
    title: '仅限专用服务端',
    description: '所有功能都在服务端完成，且与原版客户端兼容。仅在专用服务端中工作。',
  },
  client_and_server: {
    title: '客户端和服务端，两端皆需',
    description: '客户端和服务端均需安装。',
  },
  client_only_server_optional: {
    title: '客户端和服务端，服务端可选',
    description: '大部分功能在客户端，但在服务端安装可启用增强功能。',
  },
  server_only_client_optional: {
    title: '客户端和服务端，客户端可选',
    description: '大部分功能在服务端，但在客户端安装可启用增强功能。',
  },
  client_or_server: {
    title: '客户端和服务端，两端皆可选',
    description: '在客户端和服务端均具备部分功能（即使只是部分）。',
  },
  client_or_server_prefers_both: {
    title: '客户端和服务端，两端均安装效果最佳',
    description: '在客户端和服务端均具备部分功能。两端均安装时体验最佳。',
  },
  unknown: {
    title: '未知环境',
    description: '该版本的环境无法确定。',
  },
}
