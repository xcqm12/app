-- v3 environment 接管旧 4 个 side type 字段
-- 跟进 modrinth 上游 ef04dcc37 PR + 20250523174544_project-versions-environments.sql
--
-- 依赖：202604251530001_add_environment_loader_field.sql 已创建 environment loader_field（optional=true）
--
-- 步骤：
-- 1. 把现有版本数据从老 4 字段聚合映射到 environment 字段
-- 2. 清理 version_fields 中老 4 字段的残留记录
-- 3. 切换 loader_fields_loaders 关联（mod/plugin 等 loader 改为绑定 environment）
-- 4. 删除老 4 个 loader_fields
-- 5. environment 改为必填（optional=false）
-- 6. mods 表加 side_types_migration_review_status 字段（自动迁移结果待审核标识）

DO LANGUAGE plpgsql $$
DECLARE
    VAR_env_field_id INT;
    VAR_env_field_enum_id INT;
BEGIN
    SELECT id INTO VAR_env_field_id FROM loader_fields WHERE field = 'environment';
    SELECT id INTO VAR_env_field_enum_id FROM loader_field_enums WHERE enum_name = 'environment';

    IF VAR_env_field_id IS NULL OR VAR_env_field_enum_id IS NULL THEN
        RAISE EXCEPTION '前序迁移 202604251530001_add_environment_loader_field 未执行，先执行该迁移';
    END IF;

    -- ==========================================================================
    -- 1. 回填：根据老 4 字段值聚合派生 environment 值
    --    映射规则与 v2_reroute::convert_side_types_v3 反向一致
    -- ==========================================================================
    INSERT INTO version_fields (version_id, field_id, enum_value)
        SELECT vf.version_id, VAR_env_field_id, (
            SELECT id
            FROM loader_field_enum_values
            WHERE enum_id = VAR_env_field_enum_id
            AND value = (
                CASE jsonb_object_agg(lf.field, vf.int_value)
                    WHEN '{ "server_only": 0, "singleplayer": 0, "client_and_server": 0, "client_only": 1 }'::jsonb THEN 'client_only'
                    WHEN '{ "server_only": 0, "singleplayer": 0, "client_and_server": 1, "client_only": 0 }'::jsonb THEN 'client_and_server'
                    WHEN '{ "server_only": 0, "singleplayer": 0, "client_and_server": 1, "client_only": 1 }'::jsonb THEN 'client_only_server_optional'
                    WHEN '{ "server_only": 0, "singleplayer": 1, "client_and_server": 0, "client_only": 0 }'::jsonb THEN 'singleplayer_only'
                    WHEN '{ "server_only": 0, "singleplayer": 1, "client_and_server": 0, "client_only": 1 }'::jsonb THEN 'client_only'
                    WHEN '{ "server_only": 0, "singleplayer": 1, "client_and_server": 1, "client_only": 0 }'::jsonb THEN 'client_and_server'
                    WHEN '{ "server_only": 0, "singleplayer": 1, "client_and_server": 1, "client_only": 1 }'::jsonb THEN 'client_only_server_optional'
                    WHEN '{ "server_only": 1, "singleplayer": 0, "client_and_server": 0, "client_only": 0 }'::jsonb THEN 'server_only'
                    WHEN '{ "server_only": 1, "singleplayer": 0, "client_and_server": 0, "client_only": 1 }'::jsonb THEN 'client_or_server'
                    WHEN '{ "server_only": 1, "singleplayer": 0, "client_and_server": 1, "client_only": 0 }'::jsonb THEN 'server_only_client_optional'
                    WHEN '{ "server_only": 1, "singleplayer": 0, "client_and_server": 1, "client_only": 1 }'::jsonb THEN 'client_or_server_prefers_both'
                    WHEN '{ "server_only": 1, "singleplayer": 1, "client_and_server": 0, "client_only": 0 }'::jsonb THEN 'server_only'
                    WHEN '{ "server_only": 1, "singleplayer": 1, "client_and_server": 0, "client_only": 1 }'::jsonb THEN 'client_or_server'
                    WHEN '{ "server_only": 1, "singleplayer": 1, "client_and_server": 1, "client_only": 0 }'::jsonb THEN 'server_only_client_optional'
                    WHEN '{ "server_only": 1, "singleplayer": 1, "client_and_server": 1, "client_only": 1 }'::jsonb THEN 'client_or_server_prefers_both'
                    ELSE 'unknown'
                END
            )
        )
        FROM version_fields vf
        JOIN loader_fields lf ON vf.field_id = lf.id
        WHERE lf.field IN ('server_only', 'singleplayer', 'client_and_server', 'client_only')
        AND NOT EXISTS (
            SELECT 1 FROM version_fields vf2
            WHERE vf2.version_id = vf.version_id AND vf2.field_id = VAR_env_field_id
        )
        GROUP BY vf.version_id
        HAVING COUNT(DISTINCT lf.field) = 4;

    -- ==========================================================================
    -- 2. 清理 version_fields 中老 4 字段的残留记录
    -- ==========================================================================
    DELETE FROM version_fields
        WHERE field_id IN (
            SELECT id FROM loader_fields
            WHERE field IN ('server_only', 'singleplayer', 'client_and_server', 'client_only')
        );

    -- ==========================================================================
    -- 3. 切换 loader_fields_loaders 关联：老 4 字段的关联改为 environment
    -- ==========================================================================
    ALTER TABLE loader_fields_loaders DROP CONSTRAINT IF EXISTS unique_loader_field;
    ALTER TABLE loader_fields_loaders DROP CONSTRAINT IF EXISTS loader_fields_loaders_pkey;
    ALTER TABLE loader_fields_loaders REPLICA IDENTITY FULL;

    UPDATE loader_fields_loaders
        SET loader_field_id = VAR_env_field_id
        WHERE loader_field_id IN (
            SELECT id FROM loader_fields
            WHERE field IN ('server_only', 'singleplayer', 'client_and_server', 'client_only')
        );

    -- 去重（多个老字段可能映射到同一个 environment 字段，造成 (loader_id, environment) 重复）
    DELETE FROM loader_fields_loaders
        WHERE ctid NOT IN (
            SELECT MIN(ctid)
            FROM loader_fields_loaders
            GROUP BY loader_id, loader_field_id
        );

    ALTER TABLE loader_fields_loaders ADD PRIMARY KEY (loader_id, loader_field_id);
    ALTER TABLE loader_fields_loaders REPLICA IDENTITY DEFAULT;

    -- ==========================================================================
    -- 4. 删除老 4 个 loader_fields
    -- ==========================================================================
    DELETE FROM loader_fields
        WHERE field IN ('server_only', 'singleplayer', 'client_and_server', 'client_only');

    -- ==========================================================================
    -- 5. environment 改为 mandatory
    -- ==========================================================================
    UPDATE loader_fields SET optional = FALSE WHERE id = VAR_env_field_id;

    -- ==========================================================================
    -- 6. mods 表加 side_types_migration_review_status 字段
    --    标识该项目的 environment 字段是否已审核通过（自动迁移可能不准确）
    -- ==========================================================================
    ALTER TABLE mods
        ADD COLUMN IF NOT EXISTS side_types_migration_review_status VARCHAR(64) NOT NULL DEFAULT 'reviewed'
        CHECK (side_types_migration_review_status IN ('reviewed', 'pending'));

    UPDATE mods SET side_types_migration_review_status = 'pending';
END;
$$;
