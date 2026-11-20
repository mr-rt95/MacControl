//
//  PrivilegedPolicy.swift
//  MacControlCore
//

import Foundation

/// Input validation for privileged requests. Pure functions, so every rule is unit-tested.
/// The helper applies them to each request; nothing is trusted just because the app sent it.
public enum PrivilegedPolicy {

    /// Folders in the system `/Library` whose direct children may be moved as app leftovers.
    public static let leftoverRoots = [
        "Application Support", "Caches", "Preferences", "LaunchAgents", "LaunchDaemons",
        "PrivilegedHelperTools", "Logs"
    ]

    // MARK: - Time Machine

    /// Accepts `com.apple.TimeMachine.YYYY-MM-DD-HHMMSS[.local]` and returns the date part tmutil expects.
    public static func snapshotDate(from name: String) -> String? {
        let prefix = "com.apple.TimeMachine."
        guard name.hasPrefix(prefix) else { return nil }
        var rest = String(name.dropFirst(prefix.count))
        if rest.hasSuffix(".local") { rest = String(rest.dropLast(".local".count)) }
        let pattern = #"^\d{4}-\d{2}-\d{2}-\d{6}$"#
        return rest.range(of: pattern, options: .regularExpression) != nil ? rest : nil
    }

    // MARK: - Launchd

    /// A reverse-DNS style label, never an Apple one.
    public static func isValidThirdPartyLabel(_ label: String) -> Bool {
        label.range(of: #"^[A-Za-z0-9._-]{3,200}$"#, options: .regularExpression) != nil
            && !label.hasPrefix("com.apple.")
    }

    /// The plist must be a direct child of `/Library/LaunchDaemons` (checked on the real, symlink-resolved path).
    public static func isSystemDaemonPlist(path: String, systemLibrary: String = "/Library") -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension == "plist" else { return false }
        let directory = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        return directory == URL(fileURLWithPath: systemLibrary).appendingPathComponent("LaunchDaemons").resolvingSymlinksInPath().path
    }

    // MARK: - System leftovers

    /// A leftover is accepted only when it is a *direct child* of one of `leftoverRoots`, is not a symbolic link,
    /// and its name belongs to the (non-Apple) bundle identifier the app claims to be removing.
    public static func validateLeftover(path: String, bundleIdentifier: String,
                                        systemLibrary: String = "/Library") -> HelperFailure? {
        guard let identifier = LeftoverFinder.usable(identifier: bundleIdentifier),
              !identifier.hasPrefix("com.apple."), !identifier.hasPrefix(HelperConstants.machServiceName) else {
            return .invalidArgument
        }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        let library = URL(fileURLWithPath: systemLibrary).resolvingSymlinksInPath().path

        guard leftoverRoots.contains(where: { parent == library + "/" + $0 }) else { return .notAllowed }
        guard name == identifier || name.hasPrefix(identifier + ".") else { return .notAllowed }

        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return .notAllowed }       // never follow links out of /Library
        guard FileManager.default.fileExists(atPath: path) else { return .notFound }
        return nil
    }

    // MARK: - Processes

    /// Judges a process for the helper: system components stay protected, everything else (other users, root)
    /// may be asked to quit.
    public static func validateTermination(pid: Int32, name: String?, path: String?, helperPID: Int32 = getpid()) -> HelperFailure? {
        guard pid > 1 else { return .protectedTarget }
        guard let name = name else { return .notFound }
        // Reuse the app-side rules; pass the same uid for owner and current user so only protection matters.
        let verdict = ProcessSafety.verdict(name: name, path: path, ownerUID: 0, pid: pid, currentUID: 0, ownPID: helperPID)
        switch verdict {
        case .allowed, .otherUser: return nil
        case .protectedSystem, .ownProcess: return .protectedTarget
        case .gone: return .notFound
        }
    }
}
