import Darwin
import Foundation

/// Use a dedicated, user-owned directory: its permissions are tightened to 0700.
public struct HistoryFile: Sendable {
    public let url: URL
    public static let maximumItemCount = 200
    // Includes base64 image data and up to six-byte JSON escapes for each text byte.
    public static let maximumArchiveBytes = 128 * 1024 * 1024
    public enum ArchiveError: Error {
        case unsupportedVersion, unsafePath, oversizedArchive, invalidContents
    }

    private struct Archive: Codable {
        let version: Int
        let clips: [Clip]
        private enum CodingKeys: String, CodingKey { case version, clips }

        init(clips: [Clip]) { version = 2; self.clips = clips }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            guard version == 1 || version == 2 else { throw ArchiveError.unsupportedVersion }
            var items = try container.nestedUnkeyedContainer(forKey: .clips)
            var decoded: [Clip] = []
            while !items.isAtEnd {
                guard decoded.count < maximumItemCount else { throw ArchiveError.invalidContents }
                decoded.append(try items.decode(Clip.self))
            }
            if version == 1 && decoded.contains(where: { $0.isImage }) { throw ArchiveError.invalidContents }
            try HistoryFile.validate(decoded)
            clips = decoded
        }
    }

    public init(url: URL) { self.url = url }

    public func load() throws -> [Clip] {
        try autoreleasepool { try readArchive() }
    }

    private func readArchive() throws -> [Clip] {
        guard let directory = try openDirectory(create: false) else { return [] }
        defer { close(directory) }
        let file = openat(directory, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else {
            if errno == ENOENT { return [] }
            throw posixError()
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else { throw posixError() }
        try validateFile(info)
        guard info.st_size <= Self.maximumArchiveBytes else { throw ArchiveError.oversizedArchive }
        guard fchmod(file, 0o600) == 0 else { throw posixError() }
        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(file, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if count == 0 { break }
            guard data.count <= Self.maximumArchiveBytes - count else { throw ArchiveError.oversizedArchive }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try JSONDecoder().decode(Archive.self, from: data).clips
    }

    public func save(_ clips: [Clip]) throws {
        try Self.validate(clips)
        guard let directory = try openDirectory(create: !clips.isEmpty) else { return }
        defer { close(directory) }
        try validateExistingFile(in: directory)
        if clips.isEmpty {
            guard unlinkat(directory, url.lastPathComponent, 0) == 0 || errno == ENOENT else { throw posixError() }
            return
        }
        let temporary = ".history-\(UUID().uuidString).tmp"
        let file = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw posixError() }
        defer { close(file); _ = unlinkat(directory, temporary, 0) }
        var writtenBytes = 0
        func append(_ data: Data) throws {
            guard data.count <= Self.maximumArchiveBytes - writtenBytes else { throw ArchiveError.oversizedArchive }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = write(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw posixError()
                    }
                    guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                    offset += count
                }
            }
            writtenBytes += data.count
        }
        // The version-2 format is unchanged. Encode one entry at a time so an image-heavy
        // archive does not need a second complete base64 representation in memory.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        try append(Data("{\"version\":2,\"clips\":[".utf8))
        for (index, clip) in clips.enumerated() {
            if index > 0 { try append(Data(",".utf8)) }
            try autoreleasepool { try append(encoder.encode(clip)) }
        }
        try append(Data("]}".utf8))
        guard fsync(file) == 0 else { throw posixError() }
        // Descriptor-relative operations do not follow a replaced directory or destination symlink.
        guard renameat(directory, temporary, directory, url.lastPathComponent) == 0 else { throw posixError() }
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        let directory = url.deletingLastPathComponent()
        if create {
            try Foundation.FileManager.default.createDirectory(at: directory.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            guard mkdir(directory.path, 0o700) == 0 || errno == EEXIST else { throw posixError() }
        }
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if !create && errno == ENOENT { return nil }
            throw posixError()
        }
        do {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { throw posixError() }
            guard info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR else { throw ArchiveError.unsafePath }
            guard fchmod(descriptor, 0o700) == 0 else { throw posixError() }
            return descriptor
        } catch { close(descriptor); throw error }
    }

    private func validateExistingFile(in directory: Int32) throws {
        var info = stat()
        guard fstatat(directory, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return }
            throw posixError()
        }
        try validateFile(info)
    }

    private func validateFile(_ info: stat) throws {
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1 else {
            throw ArchiveError.unsafePath
        }
    }

    private static func validate(_ clips: [Clip]) throws {
        guard clips.count <= maximumItemCount, Set(clips.map(\.id)).count == clips.count,
              clips.reduce(0, { $0 + $1.imageByteCount }) <= ClipboardHistory.maximumImageHistoryBytes,
              clips.allSatisfy({ ($0.isImage ? $0.text.isEmpty : ClipboardHistory.accepts($0.text)) && $0.sourceName.utf8.count <= 1024 }) else {
            throw ArchiveError.invalidContents
        }
    }

    private func posixError() -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
