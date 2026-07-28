use std::collections::HashMap;

use super::ApiError;
use super::v3::project_creation::CreateError;
use crate::models::v2::projects::LegacySideType;
use crate::util::actix::{
    MultipartSegment, MultipartSegmentData, generate_multipart,
};
use actix_multipart::Multipart;
use actix_web::HttpResponse;
use actix_web::http::header::{
    ContentDisposition, HeaderMap, TryIntoHeaderPair,
};
use futures::{Future, StreamExt, stream};
use serde_json::{Value, json};

// 提取 OK 状态的 JSON 响应
pub async fn extract_ok_json<T>(
    response: HttpResponse,
) -> Result<T, HttpResponse>
where
    T: serde::de::DeserializeOwned,
{
    // 如果响应状态是 StatusCode::OK，解析 JSON 并返回
    if response.status() == actix_web::http::StatusCode::OK {
        let failure_http_response = || {
            HttpResponse::InternalServerError().json(json!({
                "error": "reroute_error",
                "description": "无法解析 V2 路由重定向的响应。"
            }))
        };
        // 从 HttpResponse 中提取 JSON，进行修改，然后重新生成 HttpResponse
        let body = response.into_body();
        let bytes = actix_web::body::to_bytes(body)
            .await
            .map_err(|_| failure_http_response())?;
        let json_value: T = serde_json::from_slice(&bytes)
            .map_err(|_| failure_http_response())?;
        Ok(json_value)
    } else {
        Err(response)
    }
}

// 仅移除 404 响应的主体
// 不应在回退无路由找到的处理程序中使用
pub fn flatten_404_error(res: ApiError) -> Result<HttpResponse, ApiError> {
    match res {
        ApiError::NotFound => Ok(HttpResponse::NotFound().body("")),
        _ => Err(res),
    }
}

// 允许内部修改 actix multipart 文件
// 预期：
// 1. 一个 JSON 段
// 2. 任意数量的其他二进制段
// 'closure' 使用 JSON 值和其他段的内容处置进行调用
pub async fn alter_actix_multipart<T, U, Fut>(
    mut multipart: Multipart,
    mut headers: HeaderMap,
    mut closure: impl FnMut(T, Vec<ContentDisposition>) -> Fut,
) -> Result<Multipart, CreateError>
where
    T: serde::de::DeserializeOwned,
    U: serde::Serialize,
    Fut: Future<Output = Result<U, CreateError>>,
{
    let mut segments: Vec<MultipartSegment> = Vec::new();

    let mut json = None;
    let mut json_segment = None;
    let mut content_dispositions = Vec::new();

    if let Some(field) = multipart.next().await {
        let mut field = field?;
        let content_disposition = field.content_disposition().cloned();
        let field_name = content_disposition
            .as_ref()
            .and_then(|cd| cd.get_name())
            .unwrap_or("");
        let field_filename = content_disposition
            .as_ref()
            .and_then(|cd| cd.get_filename());
        let field_content_type = field.content_type();
        let field_content_type = field_content_type.map(|ct| ct.to_string());

        let mut buffer = Vec::new();
        while let Some(chunk) = field.next().await {
            let data = chunk?;
            buffer.extend_from_slice(&data);
        }

        {
            let json_value: T = serde_json::from_slice(&buffer)?;
            json = Some(json_value);
        }

        json_segment = Some(MultipartSegment {
            name: field_name.to_string(),
            filename: field_filename.map(|s| s.to_string()),
            content_type: field_content_type,
            data: MultipartSegmentData::Binary(vec![]), // 初始化为空，将在之后完成
        });
    }

    while let Some(field) = multipart.next().await {
        let mut field = field?;
        let content_disposition = field.content_disposition().cloned();
        let field_name = content_disposition
            .as_ref()
            .and_then(|cd| cd.get_name())
            .unwrap_or("")
            .to_string();
        let field_filename = content_disposition
            .as_ref()
            .and_then(|cd| cd.get_filename())
            .map(|s| s.to_string());
        let field_content_type = field.content_type();
        let field_content_type = field_content_type.map(|ct| ct.to_string());

        let mut buffer = Vec::new();
        while let Some(chunk) = field.next().await {
            let data = chunk?;
            buffer.extend_from_slice(&data);
        }

        if let Some(cd) = content_disposition {
            content_dispositions.push(cd);
        }
        segments.push(MultipartSegment {
            name: field_name,
            filename: field_filename,
            content_type: field_content_type,
            data: MultipartSegmentData::Binary(buffer),
        })
    }

    // 完成 JSON 段，带有聚合的内容处置
    {
        let json_value = json.ok_or(CreateError::InvalidInput(
            "在 multipart 中未找到 JSON 段。".to_string(),
        ))?;
        let mut json_segment =
            json_segment.ok_or(CreateError::InvalidInput(
                "在 multipart 中未找到 JSON 段。".to_string(),
            ))?;

        // 使用 JSON 值和其他段的名称调用 closure
        let json_value: U = closure(json_value, content_dispositions).await?;
        let buffer = serde_json::to_vec(&json_value)?;
        json_segment.data = MultipartSegmentData::Binary(buffer);

        // 将 JSON 段插入到开头
        segments.insert(0, json_segment);
    }

    let (boundary, payload) = generate_multipart(segments);

    match (
        "Content-Type",
        format!("multipart/form-data; boundary={}", boundary).as_str(),
    )
        .try_into_pair()
    {
        Ok((key, value)) => {
            headers.insert(key, value);
        }
        Err(err) => {
            CreateError::InvalidInput(format!(
                "插入测试头时出错： {:?}。",
                err
            ));
        }
    };

    let new_multipart =
        Multipart::new(&headers, stream::once(async { Ok(payload) }));

    Ok(new_multipart)
}

// 将 "client_side" 和 "server_side" 对转换为 v3 environment 单字段
// 跟进上游 ef04dcc37：v3 已用 environment 取代旧的 4 个 bool 字段
pub fn convert_side_types_v3(
    client_side: LegacySideType,
    server_side: LegacySideType,
) -> HashMap<String, Value> {
    use LegacySideType::{Optional, Required, Unknown, Unsupported};

    let environment = match (client_side, server_side) {
        (Required, Required) => "client_and_server",
        (Required, Optional) => "client_only_server_optional",
        (Required, Unsupported) | (Required, Unknown) => "client_only",
        (Optional, Required) => "server_only_client_optional",
        (Optional, Optional) => "client_or_server",
        (Optional, Unsupported) | (Optional, Unknown) => "client_only",
        (Unsupported, Required) | (Unknown, Required) => "server_only",
        (Unsupported, Optional) | (Unknown, Optional) => "server_only",
        _ => "unknown",
    };

    let mut fields = HashMap::new();
    fields.insert("environment".to_string(), json!(environment));
    fields
}

// 将插件加载器从 v2 转换为 v3，用于搜索 facets
// 在每个一级和二级（v2 中允许的）中，我们将每个实例转换为：
// "project_type:mod" 到 "project_type:plugin" 或 "project_type:mod"
pub fn convert_plugin_loader_facets_v3(
    facets: Vec<Vec<String>>,
) -> Vec<Vec<String>> {
    facets
        .into_iter()
        .map(|inner_facets| {
            if inner_facets == ["project_type:mod"] {
                vec![
                    "project_type:plugin".to_string(),
                    "project_type:datapack".to_string(),
                    "project_type:mod".to_string(),
                ]
            } else {
                inner_facets
            }
        })
        .collect::<Vec<_>>()
}

// 将 v3 environment 单字段反向转换为 v2 (client_side, server_side)
// 跟进上游 ef04dcc37：从 4 字段 bool 改为读 environment 字符串
pub fn convert_side_types_v2(
    side_types: &HashMap<String, Value>,
    project_type: Option<&str>,
) -> (LegacySideType, LegacySideType) {
    let environment = side_types
        .get("environment")
        .and_then(|x| x.as_str())
        .map(|s| s.to_string());
    convert_side_types_v2_from_env(environment.as_deref(), project_type)
}

// 客户端、服务器端反向派生（v3 environment → v2 client_side/server_side）
pub fn convert_side_types_v2_from_env(
    environment: Option<&str>,
    project_type: Option<&str>,
) -> (LegacySideType, LegacySideType) {
    use LegacySideType::{Optional, Required, Unknown, Unsupported};

    // 部分项目类型对外固定 side type（上游同样保留这部分硬规则）
    match project_type {
        Some("plugin") => return (Unsupported, Required),
        Some("datapack") => return (Optional, Required),
        Some("shader") => return (Required, Unsupported),
        Some("resourcepack") => return (Required, Unsupported),
        _ => {}
    }

    match environment.unwrap_or("unknown") {
        "client_only" => (Required, Unsupported),
        "server_only" => (Unsupported, Required),
        "singleplayer_only" => (Required, Required),
        "dedicated_server_only" => (Unsupported, Required),
        "client_and_server" => (Required, Required),
        "client_only_server_optional" => (Required, Optional),
        "server_only_client_optional" => (Optional, Required),
        "client_or_server" => (Optional, Optional),
        "client_or_server_prefers_both" => (Optional, Optional),
        _ => (Unknown, Unknown),
    }
}

// 首字母大写
pub fn capitalize_first(input: &str) -> String {
    let mut result = input.to_owned();
    if let Some(first_char) = result.get_mut(0..1) {
        first_char.make_ascii_uppercase();
    }
    result
}
