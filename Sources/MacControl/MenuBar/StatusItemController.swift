//
//  StatusItemController.swift
//  MacControl
//

import AppKit
import SwiftUI
import Combine
import MacControlCore

/// Owns the menu bar item ("52 °C · 18%") and the popover opened by clicking it.
///
/// The title is only rewritten when the text actually changes, so the item costs
/// practically nothing between refreshes.
final class StatusItemController: NSObject {

    private let monitoring: MonitoringService
    private let settings: AppSettings
    private let modes: ModesViewModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var lastTitle = ""

    init(monitoring: MonitoringService, settings: AppSettings, modes: ModesViewModel,
         openApp: @escaping () -> Void) {
        self.monitoring = monitoring
        self.modes = modes
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover(openApp: openApp)

        // Refresh when new data arrives or when the user changes what the item shows.
        Publishers.CombineLatest(monitoring.$snapshot, settings.objectWillChange.prepend(()).receive(on: DispatchQueue.main))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, _ in self?.refresh(with: snapshot) }
            .store(in: &cancellables)
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "gauge", accessibilityDescription: "MacControl")
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover(openApp: @escaping () -> Void) {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarSummaryView(
                monitoring: monitoring,
                modes: modes,
                openApp: { [weak self] in
                    self?.popover.performClose(nil)
                    openApp()
                },
                quit: { NSApp.terminate(nil) }
            )
        )
    }

    // MARK: - Updating

    private func refresh(with snapshot: SystemSnapshot?) {
        guard let button = statusItem.button else { return }
        let content = Self.content(for: snapshot, settings: settings)

        let title = content.text
        guard title != lastTitle || content.level != .normal else { return }
        lastTitle = title

        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        switch content.level {
        case .normal: break
        case .warm:   attributes[.foregroundColor] = NSColor.systemOrange
        case .hot:    attributes[.foregroundColor] = NSColor.systemRed
        }
        button.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " " + title, attributes: attributes)
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    }

    /// Builds the item text and its severity from the selected metrics.
    static func content(for snapshot: SystemSnapshot?, settings: AppSettings) -> (text: String, level: ThermalLevel) {
        guard let snapshot = snapshot else { return ("", .normal) }

        var parts: [String] = []
        var level = ThermalLevel.normal

        if settings.menuBarShowsTemperature, let temperature = snapshot.cpuTemperature {
            parts.append(Formatters.temperature(temperature))
            level = max(level, ThermalLevel.classify(celsius: temperature, category: .cpu))
        }
        if settings.menuBarShowsCPU {
            parts.append(Formatters.percent(snapshot.cpu.total))
            if snapshot.cpu.total >= 0.9 { level = max(level, .warm) }
        }
        if settings.menuBarShowsMemory {
            parts.append(Formatters.percent(snapshot.memory.usedFraction))
            switch snapshot.memory.pressure {
            case .normal: break
            case .warning: level = max(level, .warm)
            case .critical: level = max(level, .hot)
            }
        }
        return (parts.joined(separator: " · "), level)
    }

    // MARK: - Actions

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
