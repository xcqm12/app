-- map loader 关联 game_versions 字段：地图对 MC 版本敏感，需在版本中绑定 game_versions
-- 注意：不关联 environment（地图无客户端/服务端区分）
INSERT INTO loader_fields_loaders (loader_id, loader_field_id) VALUES (30, 3)
ON CONFLICT DO NOTHING;
