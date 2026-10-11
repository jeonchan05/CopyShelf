import Foundation

private enum ContentIdentity: Hashable { case text(String), image(String) }

public struct Clip: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let image: ClipboardImage?
    public let copiedAt: Date
    public let sourceName: String

    public init(id: UUID = UUID(), text: String, copiedAt: Date = Date(), sourceName: String = "") {
        self.id = id
        self.text = text
        image = nil
        self.copiedAt = copiedAt
        self.sourceName = sourceName
    }

    public init(id: UUID = UUID(), image: ClipboardImage, copiedAt: Date = Date(), sourceName: String = "") {
        self.id = id
        text = ""
        self.image = image
        self.copiedAt = copiedAt
        self.sourceName = sourceName
    }

    public var isImage: Bool { image != nil }
    public var contentKey: String { image.map { "image:" + $0.fingerprint } ?? "text:" + text }
    fileprivate var contentIdentity: ContentIdentity { image.map { .image($0.fingerprint) } ?? .text(text) }
    public var imageByteCount: Int { image?.pngData.count ?? 0 }
    public var searchableText: String {
        if let image { return "image screenshot capture 이미지 스크린샷 캡처 \(image.width)×\(image.height) \(image.width)x\(image.height)" }
        return text
    }

    public var preview: String {
        if let image { return "Image · \(image.width) × \(image.height)" }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public func preview(maximumCharacters: Int) -> String {
        guard maximumCharacters > 0 else { return "" }
        if isImage { return String(preview.prefix(maximumCharacters)) }
        var result = ""
        var count = 0
        var spacePending = false
        for character in text {
            if character.isWhitespace { spacePending = !result.isEmpty; continue }
            if spacePending {
                guard count + 1 < maximumCharacters else { break }
                result.append(" "); count += 1; spacePending = false
            }
            result.append(character); count += 1
            if count == maximumCharacters { break }
        }
        return result
    }
}

public struct ClipboardHistory: Sendable {
    public static let maximumTextBytes = 65_536
    public static let maximumImageHistoryBytes = 32 * 1024 * 1024
    public let limit: Int
    public let imageByteLimit: Int
    public private(set) var clips: [Clip]

    public init(clips: [Clip] = [], limit: Int = 200, imageByteLimit: Int = maximumImageHistoryBytes) {
        self.limit = min(max(1, limit), 200)
        self.imageByteLimit = min(max(0, imageByteLimit), Self.maximumImageHistoryBytes)
        var seen = Set<ContentIdentity>()
        self.clips = Array(clips.filter {
            ($0.image != nil ? $0.text.isEmpty : Self.accepts($0.text)) && seen.insert($0.contentIdentity).inserted
        }.prefix(self.limit))
        trim()
    }

    public static func accepts(_ text: String) -> Bool {
        text.utf8.count <= maximumTextBytes &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    public mutating func record(_ text: String, sourceName: String = "", at date: Date = Date()) -> Bool {
        guard Self.accepts(text) else { return false }
        return record(Clip(text: text, copiedAt: date, sourceName: sourceName))
    }

    @discardableResult
    public mutating func record(_ image: ClipboardImage, sourceName: String = "", at date: Date = Date()) -> Bool {
        guard image.pngData.count <= imageByteLimit else { return false }
        return record(Clip(image: image, copiedAt: date, sourceName: sourceName))
    }

    private mutating func record(_ clip: Clip) -> Bool {
        let identity = clip.contentIdentity
        if clips.first?.contentIdentity == identity { return false }
        let existingIndex = clips.firstIndex { $0.contentIdentity == identity }
        let existingID = existingIndex.map { clips[$0].id } ?? clip.id
        if let existingIndex { clips.remove(at: existingIndex) }
        let source = clip.sourceName.utf8.count <= 1024 ? clip.sourceName : ""
        let entry = clip.image.map { Clip(id: existingID, image: $0, copiedAt: clip.copiedAt, sourceName: source) }
            ?? Clip(id: existingID, text: clip.text, copiedAt: clip.copiedAt, sourceName: source)
        clips.insert(entry, at: 0)
        trim()
        return true
    }

    private mutating func trim() {
        var bytes = clips.reduce(0) { $0 + $1.imageByteCount }
        while clips.count > limit || bytes > imageByteLimit {
            bytes -= clips.removeLast().imageByteCount
        }
    }

    public func search(_ query: String) -> [Clip] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return clips }
        return clips.filter { clip in
            words.allSatisfy {
                clip.searchableText.localizedStandardContains($0) || clip.sourceName.localizedStandardContains($0)
            }
        }
    }

    public mutating func remove(id: UUID) { clips.removeAll { $0.id == id } }
    public mutating func clear() { clips.removeAll() }
}

public enum CapturePolicy {
    public static let excludedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"
    ]
    public static let excludedApps: Set<String> = [
        "com.apple.Passwords", "com.agilebits.onepassword7", "com.1password.1password",
        "com.bitwarden.desktop"
    ]

    public static func shouldCapture(types: Set<String>, sourceBundleID: String?, secureInput: Bool,
                                     additionalSourceBundleIDs: Set<String> = []) -> Bool {
        !secureInput && excludedTypes.isDisjoint(with: types) &&
        !excludedApps.contains(sourceBundleID ?? "") &&
        excludedApps.isDisjoint(with: additionalSourceBundleIDs) &&
        !types.contains("public.file-url")
    }
}

public struct PasteAttempt: Sendable {
    public let id = UUID()
    public let clipboardChangeCount: Int

    public init(clipboardChangeCount: Int) { self.clipboardChangeCount = clipboardChangeCount }

    public func isCurrent(_ activeID: UUID?) -> Bool { activeID == id }
    public func clipboardIsUnchanged(_ changeCount: Int) -> Bool { changeCount == clipboardChangeCount }
}

public enum Selection {
    public static func moved(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return -1 }
        return min(max(index + delta, 0), count - 1)
    }
}
