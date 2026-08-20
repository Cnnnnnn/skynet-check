import Foundation

public struct SkynetPermissionAudit: Equatable, Sendable {
    public let directoryMode: Int?
    public let sessionMode: Int?
    public let configMode: Int?

    public init(
        directoryMode: Int?,
        sessionMode: Int?,
        configMode: Int?
    ) {
        self.directoryMode = directoryMode
        self.sessionMode = sessionMode
        self.configMode = configMode
    }

    public var hasDirectory: Bool {
        directoryMode != nil
    }

    public var needsRepair: Bool {
        directoryMode.map { $0 != 0o700 } == true
            || sessionMode.map { $0 != 0o600 } == true
            || configMode.map { $0 != 0o600 } == true
    }
}

public struct SkynetPermissionManager {
    public let configDirectory: URL
    private let fileManager: FileManager

    public init(
        configDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".skynet-cli"),
        fileManager: FileManager = .default
    ) {
        self.configDirectory = configDirectory
        self.fileManager = fileManager
    }

    public func audit() -> SkynetPermissionAudit {
        SkynetPermissionAudit(
            directoryMode: mode(at: configDirectory),
            sessionMode: mode(
                at: configDirectory.appendingPathComponent("session.json")
            ),
            configMode: mode(
                at: configDirectory.appendingPathComponent("config.json")
            )
        )
    }

    public func repair() throws {
        guard audit().hasDirectory else {
            return
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: configDirectory.path
        )
        for filename in ["session.json", "config.json"] {
            let file = configDirectory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: file.path) else {
                continue
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: file.path
            )
        }
    }

    private func mode(at url: URL) -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            return nil
        }
        return permissions.intValue & 0o777
    }
}
