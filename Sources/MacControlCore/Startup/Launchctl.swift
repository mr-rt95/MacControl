//
//  Launchctl.swift
//  MacControlCore
//

import Foundation

/// Thin wrapper around `launchctl`, limited to the current user's GUI domain.
enum Launchctl {

    private static let path = "/bin/launchctl"

    static var userDomain: String { "gui/\(getuid())" }

    /// Running jobs: label → pid (`nil` when loaded but not running).
    static func runningJobs() -> [String: Int32?] {
        guard let result = CommandRunner.execute(path, ["list"]), result.succeeded else { return [:] }
        return parseList(result.output)
    }

    /// Labels the user has disabled in the given domain.
    static func disabledLabels(domain: String = userDomain) -> Set<String> {
        guard let result = CommandRunner.execute(path, ["print-disabled", domain]), result.succeeded else { return [] }
        return parseDisabled(result.output)
    }

    /// Disables a user agent permanently and stops it now. The plist file is left untouched.
    @discardableResult
    static func disable(label: String, plist: URL) -> Bool {
        let disabled = CommandRunner.execute(path, ["disable", "\(userDomain)/\(label)"])?.succeeded == true
        _ = CommandRunner.execute(path, ["bootout", "\(userDomain)/\(label)"])   // fails harmlessly if not loaded
        return disabled
    }

    /// Re-enables a user agent and starts it.
    @discardableResult
    static func enable(label: String, plist: URL) -> Bool {
        let enabled = CommandRunner.execute(path, ["enable", "\(userDomain)/\(label)"])?.succeeded == true
        _ = CommandRunner.execute(path, ["bootstrap", userDomain, plist.path])
        return enabled
    }

    // MARK: - Parsing (pure, unit-tested)

    /// `PID<TAB>Status<TAB>Label` lines; PID is "-" for jobs that are not running.
    static func parseList(_ output: String) -> [String: Int32?] {
        var jobs: [String: Int32?] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            jobs[String(fields[2])] = Int32(fields[0])
        }
        return jobs
    }

    /// Lines such as `"com.foo.bar" => disabled` (older systems print `true`/`false`).
    static func parseDisabled(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for line in output.split(separator: "\n") {
            guard let arrow = line.range(of: "=>") else { continue }
            let value = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            guard value == "disabled" || value == "true" else { continue }
            let label = line[..<arrow.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            if !label.isEmpty { labels.insert(label) }
        }
        return labels
    }
}
