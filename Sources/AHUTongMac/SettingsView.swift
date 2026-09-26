import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("个人资料") {
                LabeledContent("姓名", value: store.profileDisplayName)
                LabeledContent("学号", value: store.studentID)
            }
            Section("登录与隐私") {
                Toggle("记住账号和密码", isOn: store.rememberBinding)
                LabeledContent("验证码识别", value: "登录时自动启用")
                Text("密码保存于 macOS 钥匙串。登录时验证码图片会由上游 AHUTong SDK 发送至其 OCR 服务进行自动识别。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("快捷键") {
                LabeledContent("刷新数据", value: "⌘R")
            }
            Section("课程通知") {
                LabeledContent("课前提醒", value: "提前 30 分钟")
                Text(store.courseNotificationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
    }
}
