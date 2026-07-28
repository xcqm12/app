use crate::routes::ApiError;
use serde::Deserialize;

pub async fn check_hcaptcha(challenge: &String) -> Result<bool, ApiError> {
    let tac_url = match dotenvy::var("TAC_URL") {
        Ok(val) => val,
        Err(_) => {
            return Ok(true);
        }
    };

    if tac_url.is_empty() || tac_url == "none" || tac_url == "false" || tac_url == "disabled" {
        return Ok(true);
    }

    if challenge.is_empty() {
        return Err(ApiError::InvalidInput("验证码不能为空".to_string()));
    }

    let client = reqwest::Client::new();

    #[derive(Deserialize, Debug)]
    struct Response {
        code: i32,
        msg: String,
        success: bool,
    }

    let url_challenge = format!("{}{}", tac_url, challenge);
    let val: Response = client
        .post(url_challenge)
        .send()
        .await
        .map_err(|_| ApiError::Turnstile)?
        .json()
        .await
        .map_err(|_| ApiError::Turnstile)?;

    if val.code == 200 && val.success {
        Ok(true)
    } else {
        Err(ApiError::InvalidInput(val.msg))
    }
}
