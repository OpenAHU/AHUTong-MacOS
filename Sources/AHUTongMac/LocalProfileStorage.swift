import AppKit
import Foundation

struct LocalProfile: Equatable {
    let displayName: String
    let avatarData: Data?

    static let empty = LocalProfile(displayName: "", avatarData: nil)
}

enum LocalProfileStorageError: LocalizedError {
    case invalidAccountID

    var errorDescription: String? {
        "当前登录账号无效，无法保存个人资料"
    }
}

enum LocalProfileStorage {
    private static let displayNameKeyPrefix = "localProfileDisplayName."
    private static let legacyDisplayNameKey = "localProfileDisplayName"

    static func loadProfile(
        for accountID: String,
        defaults: UserDefaults = .standard,
        applicationSupportDirectory: URL? = nil
    ) -> LocalProfile {
        guard let token = accountToken(for: accountID) else { return .empty }
        let displayName = defaults.string(forKey: displayNameKey(for: token)) ?? ""
        let avatarData = try? Data(
            contentsOf: avatarURL(
                for: token,
                applicationSupportDirectory: applicationSupportDirectory
            )
        )
        return LocalProfile(displayName: displayName, avatarData: avatarData)
    }

    static func saveProfile(
        displayName: String,
        avatarData: Data?,
        for accountID: String,
        defaults: UserDefaults = .standard,
        applicationSupportDirectory: URL? = nil
    ) throws {
        guard let token = accountToken(for: accountID) else {
            throw LocalProfileStorageError.invalidAccountID
        }

        let key = displayNameKey(for: token)
        if displayName.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(displayName, forKey: key)
        }

        let url = try avatarURL(
            for: token,
            applicationSupportDirectory: applicationSupportDirectory
        )
        if let avatarData {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try avatarData.write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func migrateLegacyProfile(
        to accountID: String,
        defaults: UserDefaults = .standard,
        applicationSupportDirectory: URL? = nil
    ) throws {
        guard accountToken(for: accountID) != nil else { return }

        let legacyName = defaults.string(forKey: legacyDisplayNameKey) ?? ""
        let legacyURL = try legacyAvatarURL(
            applicationSupportDirectory: applicationSupportDirectory
        )
        let legacyAvatarData = try? Data(contentsOf: legacyURL)
        guard !legacyName.isEmpty || legacyAvatarData != nil else { return }

        let current = loadProfile(
            for: accountID,
            defaults: defaults,
            applicationSupportDirectory: applicationSupportDirectory
        )
        try saveProfile(
            displayName: current.displayName.isEmpty ? legacyName : current.displayName,
            avatarData: current.avatarData ?? legacyAvatarData,
            for: accountID,
            defaults: defaults,
            applicationSupportDirectory: applicationSupportDirectory
        )

        defaults.removeObject(forKey: legacyDisplayNameKey)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try FileManager.default.removeItem(at: legacyURL)
        }
    }

    private static func accountToken(for accountID: String) -> String? {
        let normalizedID = accountID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedID.isEmpty else { return nil }
        return Data(normalizedID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func displayNameKey(for token: String) -> String {
        displayNameKeyPrefix + token
    }

    private static func avatarURL(
        for token: String,
        applicationSupportDirectory: URL?
    ) throws -> URL {
        try supportDirectory(applicationSupportDirectory)
            .appendingPathComponent("AHUTong", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
            .appendingPathComponent("profile-avatar.png")
    }

    private static func legacyAvatarURL(
        applicationSupportDirectory: URL?
    ) throws -> URL {
        try supportDirectory(applicationSupportDirectory)
            .appendingPathComponent("AHUTong", isDirectory: true)
            .appendingPathComponent("profile-avatar.png")
    }

    private static func supportDirectory(_ override: URL?) throws -> URL {
        if let override { return override }
        return try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}

enum ProfileImageError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "无法读取所选图片，请选择有效的 PNG、JPEG、HEIC 或其他图像文件"
    }
}

enum ProfileImageProcessor {
    static func squarePNGData(from url: URL, dimension: CGFloat = 512) throws -> Data {
        guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0 else {
            throw ProfileImageError.unreadable
        }

        let side = min(source.size.width, source.size.height)
        let sourceRect = NSRect(
            x: (source.size.width - side) / 2,
            y: (source.size.height - side) / 2,
            width: side,
            height: side
        )
        let pixelDimension = Int(dimension)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelDimension,
            pixelsHigh: pixelDimension,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ProfileImageError.unreadable
        }

        let targetSize = NSSize(width: dimension, height: dimension)
        bitmap.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ProfileImageError.unreadable
        }
        return png
    }
}
