//
//  RootView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Sections available in the sidebar.
enum Screen: String, CaseIterable, Identifiable {
    case diagnosis, overview, processor, memory, disk, network, sensors, history, events, health
    case cleanup, processes, apps, startup, speedup, files, activity
    case modes, report, permissions

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .diagnosis: return "Diagnosis"
        case .overview:  return "Overview"
        case .processor: return "Processor"
        case .memory:    return "Memory"
        case .disk:      return "Disk"
        case .network:   return "Network"
        case .sensors:   return "Temperatures & fans"
        case .history:   return "History"
        case .events:    return "Journal"
        case .health:    return "SSD & battery"
        case .cleanup:   return "Cleanup"
        case .processes: return "Processes"
        case .apps:      return "Apps"
        case .startup:   return "Startup & services"
        case .speedup:   return "Speed up"
        case .files:     return "Large files & duplicates"
        case .activity:  return "Activity"
        case .modes:     return "Modes"
        case .report:    return "Report"
        case .permissions: return "Permissions"
        }
    }

    /// Screens with a fixed side panel scroll their own list, so the page itself must not scroll.
    var scrollsInternally: Bool { self == .apps }

    var symbol: String {
        switch self {
        case .diagnosis: return "stethoscope"
        case .overview:  return "square.grid.2x2"
        case .processor: return "cpu"
        case .memory:    return "memorychip"
        case .disk:      return "internaldrive"
        case .network:   return "network"
        case .sensors:   return "thermometer"
        case .history:   return "chart.xyaxis.line"
        case .events:    return "list.bullet.rectangle"
        case .health:    return "heart.text.square"
        case .cleanup:   return "trash"
        case .processes: return "xmark.app"
        case .apps:      return "app.badge.checkmark"
        case .startup:   return "power"
        case .speedup:   return "bolt"
        case .files:     return "doc.on.doc"
        case .activity:  return "clock.arrow.circlepath"
        case .modes:     return "leaf"
        case .report:    return "doc.text"
        case .permissions: return "lock.shield"
        }
    }
}

/// Sidebar groups.
enum ScreenSection: CaseIterable, Identifiable {
    case monitor, analysis, manage

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .monitor:  return "Monitor"
        case .analysis: return "Analysis"
        case .manage:   return "Manage"
        }
    }

    var screens: [Screen] {
        switch self {
        case .monitor:  return [.diagnosis, .overview, .processor, .memory, .disk, .network, .sensors]
        case .analysis: return [.history, .events, .health, .report]
        case .manage:   return [.modes, .cleanup, .processes, .apps, .startup, .speedup, .files, .activity, .permissions]
        }
    }
}

/// Main window: sidebar on the left, the selected screen on the right.
struct RootView: View {

    @EnvironmentObject private var monitoring: MonitoringService
    @EnvironmentObject private var management: ManagementModel
    @EnvironmentObject private var permissions: PermissionsViewModel
    @EnvironmentObject private var navigation: NavigationModel

    private var current: Screen { navigation.selection ?? .diagnosis }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $navigation.selection) {
                ForEach(ScreenSection.allCases) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.screens) { screen in
                            Label(screen.title, systemImage: screen.symbol).tag(screen)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 260)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    @ViewBuilder
    private var detail: some View {
        if let snapshot = monitoring.snapshot, current.scrollsInternally {
            VStack(alignment: .leading, spacing: 16) {
                Text(current.title).font(.largeTitle.weight(.bold))
                content(for: current, snapshot: snapshot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let snapshot = monitoring.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(current.title).font(.largeTitle.weight(.bold))
                    content(for: current, snapshot: snapshot)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text("Collecting data…").foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(for screen: Screen, snapshot: SystemSnapshot) -> some View {
        let history = monitoring.history
        let analysis = monitoring.analysis
        switch screen {
        case .diagnosis: DiagnosisView(snapshot: snapshot, analysis: analysis, navigate: { navigation.selection = $0 })
        case .overview:  OverviewView(snapshot: snapshot, history: history, analysis: analysis, navigate: { navigation.selection = $0 })
        case .processor: ProcessorView(snapshot: snapshot, history: history, throttle: analysis.throttle, helper: management.helper)
        case .memory:    MemoryView(snapshot: snapshot, history: history)
        case .disk:      DiskView(snapshot: snapshot, history: history, folders: management.folders)
        case .network:   NetworkView(snapshot: snapshot, history: history)
        case .sensors:
            SensorsView(snapshot: snapshot,
                        modelIdentifier: monitoring.modelIdentifier,
                        sensorsAvailable: monitoring.sensorsAvailable)
        case .history:
            HistoryView(store: monitoring.historyStore, refreshToken: snapshot.timestamp)
        case .events:
            EventsView(events: monitoring.events, store: monitoring.historyStore,
                       onClear: { monitoring.clearEvents() })
        case .health:
            HealthView(snapshot: snapshot, analysis: analysis)
        case .cleanup:   CleanupView(model: management.cleanup)
        case .processes: ProcessesView(groups: snapshot.processGroups, model: management.processes)
        case .apps:      AppsView(model: management.apps)
        case .startup:   StartupView(groups: snapshot.processGroups, model: management.startup)
        case .speedup:   SpeedUpView(model: management.tuning)
        case .files:     FilesView(model: management.files)
        case .activity:  ActivityView(management: management)
        case .modes:     ModesView(model: management.modes, processes: management.processes)
        case .permissions: PermissionsView(model: permissions, helper: management.helper)
        case .report:    ReportView(model: management.report, monitoring: monitoring, startup: management.startup,
                                    groups: snapshot.processGroups)
        }
    }
}
