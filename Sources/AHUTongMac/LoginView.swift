import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("登录安大通").font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("使用统一身份认证访问智慧安大")
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 14) {
                    TextField("学号", text: $store.loginStudentID)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("login.studentID")
                    SecureField("密码", text: $store.loginPassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .onSubmit { store.login() }
                        .accessibilityIdentifier("login.password")
                }
                VStack(alignment: .leading, spacing: 11) {
                    Toggle("记住账号和密码（保存到 macOS 钥匙串）", isOn: store.rememberBinding)
                    Text("账号和密码仅提交给安徽大学相关服务；登录时验证码图片会由上游 AHUTong SDK 自动发送至其 OCR 服务进行识别。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let error = store.loginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.red)
                }
                Button { store.login() } label: {
                    HStack {
                        if store.sessionPhase == .signingIn { ProgressView().controlSize(.small) }
                        Text(store.sessionPhase == .signingIn ? "正在登录并同步数据…" : "登录")
                    }
                    .frame(maxWidth: .infinity).frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.sessionPhase == .signingIn)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("login.submit")
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                    Text("密码仅保存到本地或macOS钥匙串")
                }.font(.caption).foregroundStyle(.secondary)
            }
            .padding(48)
            .frame(maxWidth: 570)
        }
        .frame(minWidth: 900, minHeight: 590)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .task {
            await store.loadSavedCredentials()
            await store.prepareCampusService()
        }
    }

    private var brandPanel: some View {
        ZStack {
            LinearGradient(colors: [Brand.blue, Brand.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.07)).frame(width: 360).offset(x: -120, y: -220)
            Circle().fill(.white.opacity(0.06)).frame(width: 280).offset(x: 130, y: 250)
            VStack(spacing: 22) {
                AppLogo(size: 104)
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
                VStack(spacing: 8) {
                    Text("安大通 for macOS").font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("便捷访问智慧安大及教务系统").font(.title3).opacity(0.82)
                }
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            .foregroundStyle(.white)
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 360, idealWidth: 430, maxWidth: 480)
    }
}
