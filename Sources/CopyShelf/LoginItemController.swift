import ServiceManagement

enum LoginItemState: Equatable {
    case disabled, enabled, requiresApproval, unavailable

    var isRegistered: Bool { self == .enabled || self == .requiresApproval }
}

@MainActor
protocol LoginItemService {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor
struct SystemLoginItemService: LoginItemService {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
final class LoginItemController {
    enum ChangeError: Error { case previewOnly }
    private let service: any LoginItemService
    let demo: Bool

    init(service: (any LoginItemService)? = nil, demo: Bool = false) {
        self.service = service ?? SystemLoginItemService()
        self.demo = demo
    }

    // macOS is the source of truth, including changes made in System Settings.
    var state: LoginItemState { service.state }

    func setEnabled(_ enabled: Bool) throws {
        guard !demo else { throw ChangeError.previewOnly }
        if enabled {
            if !state.isRegistered { try service.register() }
        } else if state.isRegistered { try service.unregister() }
    }

    func openSettings() { if !demo { service.openSettings() } }
}
