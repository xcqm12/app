-- 新增 environment loader_field（v3 单字段环境模型，对应前端 9 项 + unknown）
-- 安全策略：纯追加，不删除/修改任何现有字段
--   - 旧的 singleplayer / client_and_server / client_only / server_only 保留，所有 Rust 代码继续工作
--   - environment 设为 optional=TRUE，旧版本不必填
--   - enum_id 动态获取 MAX(id)+1，避免与本地已占用的 id (1=side_types, 2=game_versions, 3=mrpack_loaders, 4=sortware_loaders) 冲突
--   - 仅给原本支持 side type 的 loader 关联 environment 字段（与上游一致的 loader 范围）

DO LANGUAGE plpgsql $$
DECLARE
    VAR_env_field_id INT;
    VAR_env_field_enum_id INT;
BEGIN
    -- 同步 SERIAL 序列至当前最大 id（防止本地历史手动 INSERT 导致序列落后引发 PK 冲突）
    PERFORM setval(
        pg_get_serial_sequence('loader_field_enum_values', 'id'),
        COALESCE((SELECT MAX(id) FROM loader_field_enum_values), 1),
        true
    );
    PERFORM setval(
        pg_get_serial_sequence('loader_fields', 'id'),
        COALESCE((SELECT MAX(id) FROM loader_fields), 1),
        true
    );

    SELECT COALESCE(MAX(id), 0) + 1 INTO VAR_env_field_enum_id FROM loader_field_enums;

    INSERT INTO loader_field_enums (id, enum_name, ordering, hidable)
    VALUES (VAR_env_field_enum_id, 'environment', NULL, TRUE);

    INSERT INTO loader_field_enum_values (enum_id, value, ordering, created, metadata)
    VALUES
        (VAR_env_field_enum_id, 'client_and_server',              NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'client_only',                    NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'client_only_server_optional',    NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'singleplayer_only',              NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'server_only',                    NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'server_only_client_optional',    NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'dedicated_server_only',          NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'client_or_server',               NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'client_or_server_prefers_both',  NULL, NOW(), NULL),
        (VAR_env_field_enum_id, 'unknown',                        NULL, NOW(), NULL);

    INSERT INTO loader_fields (field, field_type, enum_type, optional)
    VALUES ('environment', 'enum', VAR_env_field_enum_id, TRUE)
    RETURNING id INTO VAR_env_field_id;

    INSERT INTO loader_fields_loaders (loader_id, loader_field_id)
    SELECT DISTINCT lfl.loader_id, VAR_env_field_id
    FROM loader_fields_loaders lfl
    JOIN loader_fields lf ON lfl.loader_field_id = lf.id
    WHERE lf.field IN ('server_only', 'singleplayer', 'client_and_server', 'client_only')
    ON CONFLICT DO NOTHING;
END;
$$;
