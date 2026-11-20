//
//  AppUninstaller.swift
//  MacControlCore
//

import Foundation
import AppKit

/// Everything that would be removed together with an application, for preview before confirming.
public struct UninstallPlan {
    public let app: InstalledApp
    public let leftovers: [Leftover]

    /// Leftovers that can actually be removed without administrator rights.
    public var removableLeftovers: [Leftover] { leftovers.filter { !$0.requiresAdministrator } }
    public var skippedLeftovers: [Leftover] { leftovers.filter(\.requiresAdministrator) }

    public var totalBytes: UInt64 { app.bytes + removableLeftovers.reduce(0) { $0 + $1.bytes } }
}

public enum UninstallError: Error, Equatable {
    case protectedApp
    /// The app is still running after the quit request.
    case appStillRunning
}

/// Plans and performs application removal. Everything goes to the Trash.
public final class AppUninstaller {

    private let finder: LeftoverFinder
    private let trasher: SafeTrasher

    public init(finder: LeftoverFinder = LeftoverFinder(), trasher: SafeTrasher) {
        self.finder = finder
        self.trasher = trasher
    }

    public func plan(for app: InstalledApp) -> UninstallPlan {
        UninstallPlan(app: app, leftovers: finder.find(bundleIdentifier: app.bundleIdentifier, appName: app.name))
    }

    /// Quits the app if it is running, then moves it and the chosen leftovers to the Trash.
    /// - Parameter selectedLeftovers: the leftovers the user kept ticked in the preview.
    /// - Parameter systemRemover: moves a system-wide leftover through the privileged helper and returns its
    ///   quarantine id. When `nil`, system-wide leftovers are left untouched.
    public func uninstall(_ plan: UninstallPlan, selectedLeftovers: [Leftover],
                          systemRemover: ((Leftover) -> Result<String, HelperFailure>)? = nil) throws -> TrashReport {
        guard plan.app.isRemovable else { throw UninstallError.protectedApp }
        try quitIfRunning(plan.app)

        var requests = [TrashRequest(url: plan.app.url, bytes: plan.app.bytes)]
        requests += selectedLeftovers.filter { !$0.requiresAdministrator }.map { TrashRequest(url: $0.url, bytes: $0.bytes) }
        let report = trasher.execute(requests, kind: .uninstall, title: plan.app.name)

        // System-wide leftovers go to the helper's quarantine and get their own undoable log entry.
        var failures = report.failures
        var moved: [ActionItem] = []
        if let remover = systemRemover {
            for leftover in selectedLeftovers where leftover.requiresAdministrator {
                switch remover(leftover) {
                case .success(let id):
                    moved.append(ActionItem(originalPath: leftover.url.path, trashPath: nil, bytes: leftover.bytes, quarantineID: id))
                case .failure(let failure):
                    failures.append(TrashFailure(url: leftover.url, reason: .failed(failure.rawValue)))
                }
            }
        }
        var recordID = report.recordID
        if !moved.isEmpty {
            let record = ActionRecord(kind: .uninstall, title: "\(plan.app.name) (system files)", items: moved)
            trasher.log.append(record)
            recordID = recordID ?? record.id
        }
        return TrashReport(recordID: recordID, trashed: report.trashed + moved, failures: failures)
    }

    private func quitIfRunning(_ app: InstalledApp) throws {
        guard let identifier = app.bundleIdentifier else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        guard !running.isEmpty else { return }
        running.forEach { _ = $0.terminate() }

        let deadline = Date().addingTimeInterval(10)
        while running.contains(where: { !$0.isTerminated }), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if running.contains(where: { !$0.isTerminated }) { throw UninstallError.appStillRunning }
    }
}
