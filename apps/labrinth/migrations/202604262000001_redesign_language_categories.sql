-- 汉化板块（project_type=8）重新设计：3 维 12 项 + 配 lucide SVG 图标
-- 设计:
--   维度 1 「汉化方式」: 资源包汉化 / 硬编码汉化 / 混合汉化 / 其他方式
--   维度 2 「翻译完整度」: 完整汉化 / 部分汉化 / UI 汉化 / 物品名汉化
--   维度 3 「翻译来源」: 人工翻译 / 机翻润色 / 机翻 / 社区共建
-- 关键: 所有变更按 (category, project_type) 名字匹配，不依赖 id，
--       本地 / 生产 id 不同也能正确跑通

-- ============================================================
-- 1. 重命名旧分类（不删，保留 mods_categories 引用关系）
-- ============================================================
UPDATE categories SET category = '资源包汉化'
  WHERE category = '材质包' AND project_type = 8;

UPDATE categories SET category = '混合汉化'
  WHERE category = '其他汉化' AND project_type = 8;
-- '硬编码汉化' 名字保留不变

-- ============================================================
-- 2. 给已存在的 3 条旧分类配上 lucide 图标（覆盖默认占位的问号 SVG）
-- ============================================================
-- 资源包汉化 (package - 包裹)
UPDATE categories SET icon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7.5 4.27 9 5.15"/><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/></svg>'
  WHERE category = '资源包汉化' AND project_type = 8;

-- 硬编码汉化 (code-2 - 代码标志)
UPDATE categories SET icon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m18 16 4-4-4-4"/><path d="m6 8-4 4 4 4"/><path d="m14.5 4-5 16"/></svg>'
  WHERE category = '硬编码汉化' AND project_type = 8;

-- 混合汉化 (combine - 合并图)
UPDATE categories SET icon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 18H5a3 3 0 0 1-3-3v-1"/><path d="M14 2a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2"/><path d="M20 2a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2"/><path d="m7 21 3-3-3-3"/><rect x="14" y="14" width="8" height="8" rx="2"/></svg>'
  WHERE category = '混合汉化' AND project_type = 8;

-- ============================================================
-- 3. 新增 9 条分类（带 icon 一次插入；幂等：已存在不重插）
-- ============================================================
INSERT INTO categories (category, project_type, header, icon)
SELECT v.category, 8, v.header, v.icon FROM (VALUES
  -- 维度 1 「汉化方式」补 1 项
  (
    '其他方式',
    '汉化方式',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/></svg>'
  ),
  -- 维度 2 「翻译完整度」4 项
  (
    '完整汉化',
    '翻译完整度',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 7 17l-5-5"/><path d="m22 10-7.5 7.5L13 16"/></svg>'
  ),
  (
    '部分汉化',
    '翻译完整度',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.1 2.182a10 10 0 0 1 3.8 0"/><path d="M13.9 21.818a10 10 0 0 1-3.8 0"/><path d="M17.609 3.721a10 10 0 0 1 2.69 2.7"/><path d="M2.182 13.9a10 10 0 0 1 0-3.8"/><path d="M20.279 17.609a10 10 0 0 1-2.7 2.69"/><path d="M21.818 10.1a10 10 0 0 1 0 3.8"/><path d="M3.721 6.391a10 10 0 0 1 2.7-2.69"/><path d="M6.391 20.279a10 10 0 0 1-2.69-2.7"/></svg>'
  ),
  (
    'UI 汉化',
    '翻译完整度',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M10 4v4"/><path d="M2 8h20"/><path d="M6 4v4"/></svg>'
  ),
  (
    '物品名汉化',
    '翻译完整度',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".5" fill="currentColor"/></svg>'
  ),
  -- 维度 3 「翻译来源」4 项
  (
    '人工翻译',
    '翻译来源',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.854z"/></svg>'
  ),
  (
    '机翻润色',
    '翻译来源',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72"/><path d="m14 7 3 3"/><path d="M5 6v4"/><path d="M19 14v4"/><path d="M10 2v2"/><path d="M7 8H3"/><path d="M21 16h-4"/><path d="M11 3H9"/></svg>'
  ),
  (
    '机翻',
    '翻译来源',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/></svg>'
  ),
  (
    '社区共建',
    '翻译来源',
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 21a8 8 0 0 0-16 0"/><circle cx="10" cy="8" r="5"/><path d="M22 20c0-3.37-2-6.5-4-8a5 5 0 0 0-.45-8.3"/></svg>'
  )
) AS v(category, header, icon)
WHERE NOT EXISTS (
  SELECT 1 FROM categories c
  WHERE c.category = v.category AND c.project_type = 8
);
