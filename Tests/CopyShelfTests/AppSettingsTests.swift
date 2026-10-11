import Foundation
import Testing
@testable import CopyShelf

@MainActor
struct AppSettingsTests {
    private final class TestLoginService: LoginItemService {
        enum TestError: Error { case denied }
        var state: LoginItemState = .disabled
        var registrationCount = 0
        var unregistrationCount = 0
        var settingsCount = 0
        var registrationResult: LoginItemState = .enabled
        var failsRegistration = false
        var failsUnregistration = false

        func register() throws {
            registrationCount += 1
            if failsRegistration { throw TestError.denied }
            state = registrationResult
        }
        func unregister() throws {
            unregistrationCount += 1
            if failsUnregistration { throw TestError.denied }
            state = .disabled
        }
        func openSettings() { settingsCount += 1 }
    }

    @Test func freshInstallAndOldDefaultOffStartRecordingAutomatically() {
        let name = "CopyShelf-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(AppPreferences(defaults: defaults).shouldRecord(demo: false))
        defaults.set(false, forKey: "recordingEnabled")
        let upgraded = AppPreferences(defaults: defaults)
        #expect(upgraded.shouldRecord(demo: false))
        #expect(!upgraded.hasSeenAutomaticRecording)
        upgraded.hasSeenAutomaticRecording = true
        #expect(AppPreferences(defaults: defaults).hasSeenAutomaticRecording)
    }

    @Test func ExplicitPauseSurvivesRestartUntilRecordingIsResumed() {
        let name = "CopyShelf-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.recordingEnabled = false
        let restarted = AppPreferences(defaults: defaults)
        #expect(!restarted.shouldRecord(demo: false))
        restarted.recordingEnabled = true
        #expect(AppPreferences(defaults: defaults).shouldRecord(demo: false))
    }

    @Test func demoNeverRecordsOrChangesTheAutomaticRecordingPreference() {
        let name = "CopyShelf-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        #expect(!preferences.shouldRecord(demo: true))
        #expect(defaults.object(forKey: "recordingPaused") == nil)
        #expect(defaults.object(forKey: "hasSeenAutomaticRecording") == nil)
        #expect(preferences.shouldRecord(demo: false))
    }

    @Test func openingSettingsOnlyReadsTheCurrentSystemState() {
        let service = TestLoginService()
        let controller = LoginItemController(service: service)
        #expect(controller.state == .disabled)
        service.state = .requiresApproval
        #expect(controller.state == .requiresApproval)
        service.state = .enabled
        #expect(controller.state == .enabled)
        #expect(service.registrationCount == 0)
        #expect(service.unregistrationCount == 0)
        #expect(service.settingsCount == 0)
    }

    @Test func loginRegistrationWaitsForApprovalWithoutRegisteringTwice() throws {
        let service = TestLoginService()
        service.registrationResult = .requiresApproval
        let controller = LoginItemController(service: service)
        try controller.setEnabled(true)
        #expect(controller.state == .requiresApproval)
        #expect(controller.state != .enabled)
        try controller.setEnabled(true)
        #expect(service.registrationCount == 1)
        controller.openSettings()
        #expect(service.settingsCount == 1)
        service.state = .enabled
        try controller.setEnabled(true)
        #expect(service.registrationCount == 1)
    }

    @Test func disablingAnEnabledOrPendingLoginItemUnregistersOnlyOnce() throws {
        for state in [LoginItemState.enabled, .requiresApproval] {
            let service = TestLoginService()
            service.state = state
            let controller = LoginItemController(service: service)
            try controller.setEnabled(false)
            try controller.setEnabled(false)
            #expect(controller.state == .disabled)
            #expect(service.unregistrationCount == 1)
            #expect(service.registrationCount == 0)
        }
    }

    @Test func failedLoginChangesKeepTheActualSystemState() {
        let service = TestLoginService()
        service.failsRegistration = true
        let controller = LoginItemController(service: service)
        #expect(throws: (any Error).self) { try controller.setEnabled(true) }
        #expect(controller.state == .disabled)
        service.state = .enabled
        service.failsUnregistration = true
        #expect(throws: (any Error).self) { try controller.setEnabled(false) }
        #expect(controller.state == .enabled)
    }

    @Test func demoCannotChangeLoginItemsOrOpenSystemSettings() {
        let service = TestLoginService()
        let controller = LoginItemController(service: service, demo: true)
        #expect(throws: LoginItemController.ChangeError.self) { try controller.setEnabled(true) }
        service.state = .enabled
        #expect(throws: LoginItemController.ChangeError.self) { try controller.setEnabled(false) }
        controller.openSettings()
        #expect(service.registrationCount == 0)
        #expect(service.unregistrationCount == 0)
        #expect(service.settingsCount == 0)
    }
}
