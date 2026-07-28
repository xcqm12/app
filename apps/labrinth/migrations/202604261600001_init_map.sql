-- 注册地图（map）板块所需的 loader / project_type / 分类
INSERT INTO loaders (id, loader, icon, hidable, metadata) VALUES (30, 'map',
'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"></polygon><line x1="8" y1="2" x2="8" y2="18"></line><line x1="16" y1="6" x2="16" y2="22"></line></svg>',
false, '{}');

INSERT INTO project_types (id, name) VALUES (9, 'map');

INSERT INTO loaders_project_types (joining_loader_id, joining_project_type_id) VALUES (30, 9);

-- 复用 minecraft (game id = 1)
INSERT INTO loaders_project_types_games (loader_id, project_type_id, game_id) VALUES (30, 9, 1);

-- 同步 categories 序列：历史插入若未推进序列，新增时会撞 PK 重复
SELECT setval('categories_id_seq', GREATEST((SELECT MAX(id) FROM categories), 1));

-- 资源类型（互斥维度，决定文件用途与安装方式）
INSERT INTO categories(category, project_type, header) VALUES ('完整地图', 9, '资源类型');
INSERT INTO categories(category, project_type, header) VALUES ('建筑模板', 9, '资源类型');
INSERT INTO categories(category, project_type, header) VALUES ('结构文件', 9, '资源类型');

-- 题材
INSERT INTO categories(category, project_type, header) VALUES ('冒险', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('解谜', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('跑酷', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('PVP', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('生存', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('小游戏', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('剧情', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('恐怖', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('沙盒', 9, '题材');
INSERT INTO categories(category, project_type, header) VALUES ('模拟', 9, '题材');

-- 风格（建筑模板常用）
INSERT INTO categories(category, project_type, header) VALUES ('中世纪', 9, '风格');
INSERT INTO categories(category, project_type, header) VALUES ('现代', 9, '风格');
INSERT INTO categories(category, project_type, header) VALUES ('科幻', 9, '风格');
INSERT INTO categories(category, project_type, header) VALUES ('幻想', 9, '风格');
INSERT INTO categories(category, project_type, header) VALUES ('日式', 9, '风格');
INSERT INTO categories(category, project_type, header) VALUES ('蒸汽朋克', 9, '风格');
INSERT INTO categories(category, project_type, header) VALUES ('原版', 9, '风格');

-- 规模（建筑模板常用）
INSERT INTO categories(category, project_type, header) VALUES ('小型', 9, '规模');
INSERT INTO categories(category, project_type, header) VALUES ('中型', 9, '规模');
INSERT INTO categories(category, project_type, header) VALUES ('大型', 9, '规模');
INSERT INTO categories(category, project_type, header) VALUES ('史诗', 9, '规模');

-- 玩法（完整地图常用）
INSERT INTO categories(category, project_type, header) VALUES ('单人', 9, '玩法');
INSERT INTO categories(category, project_type, header) VALUES ('多人', 9, '玩法');
INSERT INTO categories(category, project_type, header) VALUES ('合作', 9, '玩法');
INSERT INTO categories(category, project_type, header) VALUES ('对抗', 9, '玩法');

-- 同步序列，避免后续插入 PK 冲突（参考之前迁移踩过的坑）
SELECT setval('loaders_id_seq', GREATEST((SELECT MAX(id) FROM loaders), 30));
SELECT setval('project_types_id_seq', GREATEST((SELECT MAX(id) FROM project_types), 9));
