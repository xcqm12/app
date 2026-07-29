use lettre::message::Mailbox;
use lettre::message::header::ContentType;
use lettre::transport::smtp::authentication::Credentials;
use lettre::{Address, Message, SmtpTransport, Transport};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum MailError {
    #[error("环境错误")]
    Env(#[from] dotenvy::Error),
    #[error("邮箱错误: {0}")]
    Mail(#[from] lettre::error::Error),
    #[error("地址解析错误: {0}")]
    Address(#[from] lettre::address::AddressError),
    #[error("SMTP 错误: {0}")]
    Smtp(#[from] lettre::transport::smtp::Error),
}

pub fn send_email_raw(
    to: String,
    subject: String,
    body: String,
) -> Result<(), MailError> {
    let from_name =
        dotenvy::var("SMTP_FROM_NAME").unwrap_or_else(|_| "BBSMC".to_string());
    let from_user = dotenvy::var("SMTP_FROM_USER")
        .unwrap_or_else(|_| "noreply".to_string());
    let from_domain = dotenvy::var("SMTP_FROM_DOMAIN")
        .unwrap_or_else(|_| "bbsmc.org.cn".to_string());

    let smtp_host = match dotenvy::var("SMTP_HOST") {
        Ok(val) if !val.is_empty() && val != "none" && val != "false" && val != "disabled" => val,
        _ => {
            tracing::warn!("SMTP_HOST 未配置或被禁用, 跳过邮件发送");
            return Ok(());
        }
    };

    let smtp_username = match dotenvy::var("SMTP_USERNAME") {
        Ok(val) if !val.is_empty() && val != "none" && val != "false" && val != "disabled" => val,
        _ => {
            tracing::warn!("SMTP_USERNAME 未配置或被禁用, 跳过邮件发送");
            return Ok(());
        }
    };

    let smtp_password = match dotenvy::var("SMTP_PASSWORD") {
        Ok(val) if !val.is_empty() && val != "none" && val != "false" && val != "disabled" => val,
        _ => {
            tracing::warn!("SMTP_PASSWORD 未配置或被禁用, 跳过邮件发送");
            return Ok(());
        }
    };

    let email = Message::builder()
        .from(Mailbox::new(
            Some(from_name),
            Address::new(&from_user, &from_domain)?,
        ))
        .to(to.parse()?)
        .subject(subject)
        .header(ContentType::TEXT_HTML)
        .body(body)?;

    let creds = Credentials::new(smtp_username, smtp_password);

    let mailer = SmtpTransport::relay(&smtp_host)?
        .port(465)
        .credentials(creds)
        .build();

    mailer.send(&email)?;

    Ok(())
}

pub fn send_email(
    to: String,
    email_title: &str,
    email_description: &str,
    line_two: &str,
    button_info: Option<(&str, &str)>,
) -> Result<(), MailError> {
    let mut email = if button_info.is_some() {
        include_str!("button_notif.html")
    } else {
        include_str!("auth_notif.html")
    }
    .replace("{{ email_title }}", email_title)
    .replace("{{ email_description }}", email_description)
    .replace("{{ line_one }}", email_description)
    .replace("{{ line_two }}", line_two);

    if let Some((button_title, button_link)) = button_info {
        email = email
            .replace("{{ button_title }}", button_title)
            .replace("{{ button_link }}", button_link);
    }

    send_email_raw(to, email_title.to_string(), email)?;

    Ok(())
}
