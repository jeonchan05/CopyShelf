import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator()

    func applicationWillFinishLaunching(_ notification: Notification) { coordinator.prepare() }
    func applicationDidFinishLaunching(_ notification: Notification) { coordinator.start() }
    func applicationDidBecomeActive(_ notification: Notification) { coordinator.becameActive() }
    func applicationWillTerminate(_ notification: Notification) { coordinator.stop() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.reopen(hasVisibleWindows: flag)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
