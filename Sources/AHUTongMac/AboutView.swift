import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 20)
                AppLogo(size: 116)
                    .shadow(color: Brand.blue.opacity(0.25), radius: 20, y: 8)
                VStack(spacing: 7) {
                    Text("安大通 for macOS").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("版本 1.0").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("开发者：")
                        Link("阿苏塔卡", destination: URL(string: "https://github.com/Asutaka233")!)
                    }
                }
                Text("基于安大通AHUTong项目移植的macOS端安徽大学教务App，采用Swift UI + Rust开发")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: 600)
                HStack(spacing: 12) {
                    Button("查看原项目") { openURL(URL(string: "https://github.com/OpenAHU/AHUTong")!) }.buttonStyle(.borderedProminent)
                    Button("开源许可证") { openURL(URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!) }.buttonStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label("数据与隐私", systemImage: "lock.shield.fill").font(.headline)
                    Text("账号密码仅提交给安徽大学相关认证服务，并可保存在 macOS 钥匙串。登录时，上游 SDK 会将验证码图片发送至其 OCR 服务进行自动识别。安装包不含预置账号，不会把密码写入源码或普通配置文件。")
                        .foregroundStyle(.secondary)
                }.cardStyle().frame(maxWidth: 680)
                Link("https://github.com/OpenAHU/AHUTong-MacOS", destination: URL(string: "https://github.com/OpenAHU/AHUTong-MacOS")!)
                Spacer(minLength: 20)
            }
            .padding(28).frame(maxWidth: .infinity)
        }
    }
}
