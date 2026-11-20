//
//  StartupViewModel.swift
//  MacControl
//

import Foundation
import MacControlCore

/// Drives the Startup & services screen.
final class StartupViewModel: ObservableObject {

    @Published private(set) var items: [LaunchItem] = []
    @Published private(set) var loginItems: [LoginItem] = []
    @Published private(set) var removedLoginItems: [LoginItem] = []
    @Published private(set) var loginItemsLoaded = false
    @Published private(set) var isLoading = false
    @Published var banner: Banner?

    private unowned let model: ManagementModel
    private let scanner = LaunchItemsScanner()
    private let loginService = LoginItemsService()

    init(model: ManagementModel) {
        self.model = model
        removedLoginItems = loginService.disabledItems()
    }

    /// Reads launchd jobs and joins them with current CPU/memory use.
    func refresh(groups: [ProcessGroup]) {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .utility).async { [scanner] in
            let items = scanner.scan(processGroups: groups)
            DispatchQueue.main.async {
                self.items = items
                self.isLoading = false
            }
        }
    }

    /// Running jobs that cost something, heaviest first: the "heavy background services" list.
    var heavyServices: [LaunchItem] {
        items.filter { $0.isRunning }
            .sorted { $0.memoryBytes + UInt64($0.cpuPercent * 10_000_000) > $1.memoryBytes + UInt64($1.cpuPercent * 10_000_000) }
    }

    func setEnabled(_ enabled: Bool, item: LaunchItem, groups: [ProcessGroup]) {
        let client = model.helper.commandClient()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = LaunchItemController.setEnabled(enabled, item: item, helper: client)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.banner = nil
                    self.isLoading = false
                    self.refresh(groups: groups)
                case .failure(let failure):
                    self.banner = Banner(message: Self.message(for: failure), isError: true)
                }
            }
        }
    }

    var helperUsable: Bool { model.helper.isUsable }

    // MARK: - Login items (System Events, needs the user's permission)

    func loadLoginItems() {
        DispatchQueue.global(qos: .userInitiated).async { [loginService] in
            let result = loginService.list()
            DispatchQueue.main.async {
                switch result {
                case .success(let items):
                    self.loginItems = items
                    self.loginItemsLoaded = true
                    self.removedLoginItems = loginService.disabledItems()
                case .failure(let error):
                    self.banner = Banner(message: Self.message(for: error), isError: true)
                }
            }
        }
    }

    func removeLoginItem(_ item: LoginItem) {
        DispatchQueue.global(qos: .userInitiated).async { [loginService] in
            let result = loginService.disable(item)
            DispatchQueue.main.async {
                if case .failure(let error) = result { self.banner = Banner(message: Self.message(for: error), isError: true) }
                self.loadLoginItems()
            }
        }
    }

    func restoreLoginItem(_ item: LoginItem) {
        DispatchQueue.global(qos: .userInitiated).async { [loginService] in
            let result = loginService.restore(item)
            DispatchQueue.main.async {
                if case .failure(let error) = result { self.banner = Banner(message: Self.message(for: error), isError: true) }
                self.loadLoginItems()
            }
        }
    }

    // MARK: - Messages

    private static func message(for failure: LaunchItemController.Failure) -> String {
        switch failure {
        case .requiresAdministrator: return tr("This item is system-wide. Changing it needs the administrator helper (see Permissions).")
        case .protectedSystemService: return tr("Apple system services are shown for information only.")
        case .commandFailed: return tr("macOS refused the change.")
        }
    }

    private static func message(for failure: LoginItemsService.Failure) -> String {
        switch failure {
        case .permissionDenied:
            return tr("Allow MacControl to control System Events in System Settings ▸ Privacy & Security ▸ Automation.")
        case .scriptFailed(let text):
            return tr("Login items could not be changed: %@", text)
        }
    }
}
