use crate::data::api::client::AHUClient;
use anyhow::anyhow;
use reqwest::multipart;
use serde_json::Value;

const BASE_URL: &str = "https://adwmh.ahu.edu.cn";
const CAPTCHA_OCR_URL: &str = "https://openahu.org/ocr/captcha";

impl AHUClient {
    // @GET("/remind/authcode")
    pub async fn get_auth_code(&self) -> anyhow::Result<bytes::Bytes> {
        let response = self
            .http
            .get(format!("{}/remind/authcode", BASE_URL))
            .header("Cache-Control", "no-cache")
            .header("Pragma", "no-cache")
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            return Err(anyhow!(
                "authcode_request_failed_status_{}",
                status.as_u16()
            ));
        }

        let bytes = response.bytes().await?;
        if bytes.is_empty() {
            return Err(anyhow!("authcode_response_empty"));
        }

        Ok(bytes)
    }

    // @POST("/user/login")
    pub async fn login_with_captcha(
        &self,
        username: &str,
        password: &str,
        flag: i32,
        imgcode: &str,
    ) -> reqwest::Result<Value> {
        let params = [
            ("username", username),
            ("pwd", password),
            ("flag", &flag.to_string()),
            ("imgcode", imgcode),
        ];

        self.http
            .post(format!("{}/user/login", BASE_URL))
            .form(&params)
            .send()
            .await?
            .json::<Value>()
            .await
    }

    // @GET("/xzxcard/yue")
    pub async fn get_balance(&self) -> anyhow::Result<Value> {
        self.authenticated_json(self.http.get(format!("{}/xzxcard/yue", BASE_URL)))
            .await
    }

    // @GET("/xzxcard/qrcode")
    pub async fn get_qrcode(&self) -> anyhow::Result<Value> {
        self.authenticated_json(self.http.get(format!("{}/xzxcard/qrcode", BASE_URL)))
            .await
    }

    pub async fn get_captcha_result(&self, image_bytes: Vec<u8>) -> reqwest::Result<Value> {
        let part = multipart::Part::bytes(image_bytes)
            .file_name("img.jpg")
            .mime_str("image/jpg")?;

        let form = multipart::Form::new().part("captcha", part);

        // 使用临时 Client，避免把校园系统 Cookie 发送到验证码服务。
        // OCR 已迁移到具有有效 HTTPS 证书的 openahu.org，不再连接旧 IP
        // 或手动覆盖 Host。
        #[cfg(not(target_arch = "wasm32"))]
        let client = reqwest::Client::builder()
            .http1_only()
            .connect_timeout(std::time::Duration::from_secs(20))
            .timeout(std::time::Duration::from_secs(120))
            .user_agent("AHUTong/RustSDK")
            .build()?;

        #[cfg(target_arch = "wasm32")]
        let client = reqwest::Client::builder().build()?;

        client
            .post(CAPTCHA_OCR_URL)
            .header("Accept", "*/*")
            .multipart(form)
            .send()
            .await?
            .json::<Value>()
            .await
    }
}
