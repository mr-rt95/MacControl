//
//  TuningViewModel.swift
//  MacControl
//

import Foundation
import AppKit
import MacControlCore

/// Drives the Speed-up screen. Nothing is applied without the user pressing the button,
/// and every change can be reverted.
final class TuningViewModel: ObservableObject {

    @Published private(set) var applied: Set<String> = []
    @Published private(set) var restorable: Set<String> = []
    @Published private(set) var spotlightEnabled: Bool?
    @Published private(set) var busy: String?
    @Published var banner: Banner?

    private let service = TuningService()

    private var activationObserver: NSObjectProtocol?

    init(model: ManagementModel) {
        // The user flips switches in System Settings; re-read the state when they come back.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let observer = activationObserver { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [service] in
            let applied = Set(TuningRecommendation.all.filter(service.isApplied).map(\.id))
            let restorable = Set(TuningRecommendation.all.filter(service.canRestore).map(\.id))
            let spotlight = service.spotlightIndexingEnabled()
            DispatchQueue.main.async {
                self.applied = applied
                self.restorable = restorable
                self.spotlightEnabled = spotlight
            }
        }
    }

    func apply(_ rec: TuningRecommendation) {
        if rec.requiresSystemSettings {
            // macOS blocks command-line changes to this setting: guide the user to the switch instead.
            openAccessibilitySettings()
            banner = Banner(message: tr("Turn on “%@” in System Settings ▸ Accessibility ▸ Display, then return to MacControl.", tr(rec.title)))
            return
        }
        run(rec) { $0.apply(rec) } onResult: { result in
            switch result {
            case .applied: return Banner(message: tr("Applied: %@", tr(rec.title)))
            case .notAccepted:
                return Banner(message: tr("macOS did not accept this change. Turn it on in System Settings ▸ Accessibility ▸ Display."), isError: true)
            case .failed: return Banner(message: tr("The change could not be applied."), isError: true)
            }
        }
    }

    /// "Restore as it was": returns the setting to the value saved before MacControl changed it.
    func restore(_ rec: TuningRecommendation) {
        run(rec) { $0.restore(rec) } onResult: { result in
            result == .applied
                ? Banner(message: tr("Restored: %@", tr(rec.title)))
                : Banner(message: tr("The setting could not be restored."), isError: true)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display") {
            NSWorkspace.shared.open(url)
        }
    }

    private func run(_ rec: TuningRecommendation, _ work: @escaping (TuningService) -> TuningResult,
                     onResult: @escaping (TuningResult) -> Banner) {
        busy = rec.id
        DispatchQueue.global(qos: .userInitiated).async { [service] in
            let result = work(service)
            DispatchQueue.main.async {
                self.busy = nil
                self.banner = onResult(result)
                self.refresh()
            }
        }
    }
}
