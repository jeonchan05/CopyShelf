import AppKit
import Carbon
import ClipboardCore
import Foundation

@MainActor
final class ClipboardMonitor {
    private var timer: Foundation.Timer?
    private var lastChangeCount: Int
    private let pasteboard: NSPasteboard
    private let readText: (NSPasteboard) -> String?
    private let secureInput: () -> Bool
    private let readImage: (NSPasteboard, NSPasteboard.PasteboardType) -> Data?
    private let readAccessBlocked: (NSPasteboard) -> Bool
    private let uptime: () -> TimeInterval
    private var nextAccessCheck: TimeInterval = -.infinity
    private var accessBlocked = false
    private var reportedAccess: Bool?
    private var enabled = false
    private var suspended = false
    private let processor = DispatchQueue(label: "CopyShelf.capture", qos: .userInitiated)
    private var generation = 0
    private var pendingImageBytes = 0
    private var pendingCount = 0
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, .init("public.jpeg"), .init("public.heic"), .init("public.heif"),
        .init("com.compuserve.gif"), .init("com.microsoft.bmp")
    ]
    private enum Snapshot: Sendable { case text(String), image(Data) }
    var onText: ((String, String) -> Void)?
    var onClip: ((Clip) -> Void)?
    var onSkippedImage: (() -> Void)?
    var onAccessIssue: ((Bool) -> Void)?

    init(pasteboard: NSPasteboard = .general,
         secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         readText: @escaping (NSPasteboard) -> String? = { $0.string(forType: .string) },
         readImage: @escaping (NSPasteboard, NSPasteboard.PasteboardType) -> Data? = { $0.data(forType: $1) },
         readAccessBlocked: @escaping (NSPasteboard) -> Bool = {
             if #available(macOS 15.4, *) { return $0.accessBehavior == .alwaysDeny || $0.accessBehavior == .ask }
             return false
         },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.pasteboard = pasteboard
        self.secureInput = secureInput
        self.readText = readText
        self.readImage = readImage
        self.readAccessBlocked = readAccessBlocked
        self.uptime = uptime
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        invalidatePendingCaptures()
        startTimer()
    }

    private func startTimer() {
        guard enabled, !suspended, timer == nil else { return }
        nextAccessCheck = -.infinity
        let timer = Foundation.Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        enabled = false
        timer?.invalidate()
        timer = nil
        invalidatePendingCaptures()
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        timer?.invalidate(); timer = nil
        invalidatePendingCaptures()
        if !suspended { startTimer() }
    }

    func invalidatePendingCaptures() {
        generation += 1
        lastChangeCount = pasteboard.changeCount
    }

    func acknowledgeOwnWrite(changeCount: Int) { lastChangeCount = changeCount }

    func poll() {
        guard !suspended else { return }
        let changeCount = pasteboard.changeCount
        let now = uptime()
        // Check access on every new copy, but avoid repeating the same idle query four times a second.
        if changeCount != lastChangeCount || now >= nextAccessCheck {
            accessBlocked = readAccessBlocked(pasteboard)
            nextAccessCheck = now + 2
            if reportedAccess != accessBlocked { reportedAccess = accessBlocked; onAccessIssue?(accessBlocked) }
        }
        guard !accessBlocked else { lastChangeCount = changeCount; return }
        guard changeCount != lastChangeCount else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let before = metadata()
        guard allowed(before, source: app?.bundleIdentifier) else {
            if pasteboard.changeCount == changeCount { lastChangeCount = changeCount }
            return
        }
        let snapshot: Snapshot?
        if let type = Self.imageTypes.first(where: { before.types.contains($0.rawValue) }) {
            snapshot = readImage(pasteboard, type).map { .image($0) }
        } else {
            snapshot = readText(pasteboard).flatMap { ClipboardHistory.accepts($0) ? .text($0) : nil }
        }
        let after = metadata()
        guard pasteboard.changeCount == changeCount else { return }
        lastChangeCount = changeCount
        guard allowed(after, source: app?.bundleIdentifier), let snapshot else { return }
        let imageBytes: Int
        if case let .image(data) = snapshot { imageBytes = data.count } else { imageBytes = 0 }
        guard pendingCount < 32, imageBytes <= ClipboardImage.maximumInputBytes,
              pendingImageBytes <= 32 * 1024 * 1024 - imageBytes else {
            if imageBytes > 0 { onSkippedImage?() }
            return
        }
        pendingCount += 1
        pendingImageBytes += imageBytes
        let capturedGeneration = generation
        let copiedAt = Date()
        let sourceName = app?.localizedName ?? ""
        // Processing all snapshots on one queue keeps a slow image ahead of later copies.
        processor.async { [weak self] in
            let clip: Clip? = autoreleasepool {
                switch snapshot {
                case let .text(text): return Clip(text: text, copiedAt: copiedAt, sourceName: sourceName)
                case let .image(data):
                    return (try? ClipboardImage.normalising(data)).map { Clip(image: $0, copiedAt: copiedAt, sourceName: sourceName) }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingCount -= 1
                self.pendingImageBytes -= imageBytes
                guard self.generation == capturedGeneration else { return }
                if let clip {
                    self.onClip?(clip)
                    if !clip.isImage { self.onText?(clip.text, clip.sourceName) }
                } else { self.onSkippedImage?() }
            }
        }
    }

    func finishCaptures() async {
        await withCheckedContinuation { continuation in
            processor.async { DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func allowed(_ metadata: (types: Set<String>, sources: Set<String>), source: String?) -> Bool {
        CapturePolicy.shouldCapture(types: metadata.types, sourceBundleID: source,
                                    secureInput: secureInput(), additionalSourceBundleIDs: metadata.sources)
    }

    private func metadata() -> (types: Set<String>, sources: Set<String>) {
        let items = pasteboard.pasteboardItems ?? []
        let types = Set((pasteboard.types ?? []).map(\.rawValue) + items.flatMap { $0.types.map(\.rawValue) })
        let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
        return (types, Set(items.compactMap { $0.string(forType: sourceType) }))
    }
}
