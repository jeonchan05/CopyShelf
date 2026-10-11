import ClipboardCore
import Foundation

/// Batch short copy bursts, and keep only the newest snapshot during disk writes.
final class HistoryWriter: @unchecked Sendable {
    private struct Work {
        let clips: [Clip]
        let generation: Int
        let completion: @Sendable (Int, Bool) -> Void
    }
    private let file: HistoryFile
    private let queue = DispatchQueue(label: "CopyShelf.history", qos: .utility)
    private let lock = NSLock()
    private var pending: Work?
    private var writing = false
    private var scheduled: DispatchWorkItem?
    private let coalescingInterval: TimeInterval

    init(file: HistoryFile, coalescingInterval: TimeInterval = 0.35) {
        self.file = file
        self.coalescingInterval = max(0, coalescingInterval)
    }

    func submit(_ clips: [Clip], generation: Int, completion: @escaping @Sendable (Int, Bool) -> Void) {
        lock.lock()
        pending = Work(clips: clips, generation: generation, completion: completion)
        if !writing && scheduled == nil {
            let work = DispatchWorkItem { [self] in drain() }
            scheduled = work
            queue.asyncAfter(deadline: .now() + coalescingInterval, execute: work)
        }
        lock.unlock()
    }

    private func drain() {
        lock.lock()
        scheduled = nil
        writing = true
        lock.unlock()
        while true {
            lock.lock()
            guard let work = pending else { writing = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            do {
                try autoreleasepool { try file.save(work.clips) }
                work.completion(work.generation, true)
            }
            catch { work.completion(work.generation, false) }
        }
    }

    func clear() throws {
        lock.lock()
        pending = nil
        scheduled?.cancel()
        scheduled = nil
        lock.unlock()
        try queue.sync { try file.save([]) }
    }

    func finish() {
        lock.lock()
        scheduled?.cancel()
        scheduled = nil
        lock.unlock()
        queue.sync { drain() }
    }
}
