import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftName = ""
    @State private var draftAvatarData: Data?
    @State private var isSelectingAvatar = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("个人资料").font(.title2.bold())
                    Text("修改只保存在这台 Mac 上，不会同步到智慧安大")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 13) {
                ProfileAvatarView(
                    imageData: draftAvatarData,
                    fallbackName: draftName.isEmpty ? store.studentName : draftName,
                    size: 108
                )
                HStack(spacing: 10) {
                    Button("选择头像") { isSelectingAvatar = true }
                        .buttonStyle(.borderedProminent)
                    Button("移除头像") { draftAvatarData = nil }
                        .buttonStyle(.bordered)
                        .disabled(draftAvatarData == nil)
                }
            }

            Form {
                LabeledContent("显示名称") {
                    TextField(store.studentName, text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                LabeledContent("智慧安大学号", value: store.studentID)
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("恢复默认名称") { draftName = "" }
                    .buttonStyle(.borderless)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520, height: 500)
        .onAppear {
            draftName = store.localProfileName
            draftAvatarData = store.profileAvatarData
            errorMessage = nil
        }
        .fileImporter(
            isPresented: $isSelectingAvatar,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            importAvatar(from: result)
        }
    }

    private func importAvatar(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            draftAvatarData = try ProfileImageProcessor.squarePNGData(from: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try store.updateLocalProfile(displayName: draftName, avatarData: draftAvatarData)
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}

struct ProfileAvatarView: View {
    let imageData: Data?
    let fallbackName: String
    let size: CGFloat

    private var image: NSImage? {
        imageData.flatMap(NSImage.init(data:))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)))
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.blue.gradient)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
        .shadow(color: .black.opacity(0.14), radius: size * 0.08, y: size * 0.04)
    }
}
