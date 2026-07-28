import type { ComputedRef, Ref } from 'vue'
import { createContext } from './index'

export interface ProjectPageContext {
  projectV2: ComputedRef<{
    id: string
    project_type: string
    slug?: string
    [key: string]: unknown
  }>
  refreshVersions: () => Promise<void>
  /**
   * 通用失效/刷新回调，用于在创建/编辑版本后重新拉取相关数据。
   * 上游 modal 用 `invalidate()`；本地默认实现为调用 `refreshVersions()`。
   * 提供方可覆盖以同时刷新更多内容（如项目元数据、依赖等）。
   */
  invalidate?: () => Promise<void>
}

export const [injectProjectPageContext, provideProjectPageContext] =
  createContext<ProjectPageContext>('ProjectPage')
