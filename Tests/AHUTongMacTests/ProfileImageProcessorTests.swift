import AppKit
import Foundation
import Testing
@testable import AHUTongMac

struct ProfileImageProcessorTests {
    @Test("头像图片会被裁剪并缩放为 512 像素方形 PNG")
    func createsSquareAvatarPNG() throws {
        let source = NSImage(size: NSSize(width: 800, height: 400))
        source.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 400).fill()
        source.unlockFocus()

        let sourceData = try #require(source.tiffRepresentation)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tiff")
        try sourceData.write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let avatarData = try ProfileImageProcessor.squarePNGData(from: temporaryURL)
        let bitmap = try #require(NSBitmapImageRep(data: avatarData))

        #expect(bitmap.pixelsWide == 512)
        #expect(bitmap.pixelsHigh == 512)
        #expect(avatarData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("不同智慧安大账号的名称和头像相互隔离")
    func storesProfilesByAccount() throws {
        let suiteName = "LocalProfileStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: supportDirectory)
        }

        let firstAvatar = Data([0x01, 0x02, 0x03])
        try LocalProfileStorage.saveProfile(
            displayName: "账号一",
            avatarData: firstAvatar,
            for: "H000001",
            defaults: defaults,
            applicationSupportDirectory: supportDirectory
        )

        let firstProfile = LocalProfileStorage.loadProfile(
            for: "h000001",
            defaults: defaults,
            applicationSupportDirectory: supportDirectory
        )
        let untouchedProfile = LocalProfileStorage.loadProfile(
            for: "H000002",
            defaults: defaults,
            applicationSupportDirectory: supportDirectory
        )

        #expect(firstProfile == LocalProfile(displayName: "账号一", avatarData: firstAvatar))
        #expect(untouchedProfile == .empty)
    }

    @Test("旧版全局个人资料只迁移到上次登录账号")
    func migratesLegacyProfileToOneAccount() throws {
        let suiteName = "LocalProfileMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyAvatarURL = supportDirectory
            .appendingPathComponent("AHUTong", isDirectory: true)
            .appendingPathComponent("profile-avatar.png")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: supportDirectory)
        }

        defaults.set("旧版名称", forKey: "localProfileDisplayName")
        try FileManager.default.createDirectory(
            at: legacyAvatarURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyAvatar = Data([0x0A, 0x0B, 0x0C])
        try legacyAvatar.write(to: legacyAvatarURL)

        try LocalProfileStorage.migrateLegacyProfile(
            to: "H000001",
            defaults: defaults,
            applicationSupportDirectory: supportDirectory
        )

        let migratedProfile = LocalProfileStorage.loadProfile(
            for: "H000001",
            defaults: defaults,
            applicationSupportDirectory: supportDirectory
        )
        let otherProfile = LocalProfileStorage.loadProfile(
            for: "H000002",
            defaults: defaults,
            applicationSupportDirectory: supportDirectory
        )

        #expect(migratedProfile == LocalProfile(displayName: "旧版名称", avatarData: legacyAvatar))
        #expect(otherProfile == .empty)
        #expect(defaults.string(forKey: "localProfileDisplayName") == nil)
        #expect(!FileManager.default.fileExists(atPath: legacyAvatarURL.path))
    }
}
