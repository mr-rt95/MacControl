//
//  LoginItems.swift
//  MacControlCore
//

import Foundation

/// Reads and edits the user's login items through System Events.
///
/// macOS asks the user once for permission to control System Events; until it is granted,
/// calls return `.permissionDenied`. Removed items are remembered so they can be put back.
public final class LoginItemsService {

    public enum Failure: Error, Equatable {
        case permissionDenied
        case scriptFailed(String)
    }

    private let storeURL: URL?
    private let queue = DispatchQueue(label: "com.maccontrol.loginitems")

    public init(storeURL: URL? = AppSupport.directory?.appendingPathComponent("disabled-login-items.json")) {
        self.storeURL = storeURL
    }

    /// Current login items.
    public func list() -> Result<[LoginItem], Failure> {
        queue.sync {
            let script = """
            tell application "System Events"
                set output to ""
                repeat with item_ in login items
                    set output to output & (name of item_) & "\\t" & (path of item_) & "\\n"
                end repeat
                return output
            end tell
            """
            return run(script).map(Self.parse)
        }
    }

    /// Items removed earlier by MacControl, available to restore.
    public func disabledItems() -> [LoginItem] {
        guard let url = storeURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LoginItem].self, from: data)) ?? []
    }

    /// Removes the item from Login Items (the app itself is untouched) and remembers it.
    public func disable(_ item: LoginItem) -> Result<Void, Failure> {
        queue.sync {
            let escaped = Self.escape(item.name)
            switch run("tell application \"System Events\" to delete login item \"\(escaped)\"") {
            case .success:
                var stored = disabledItems().filter { $0.path != item.path }
                stored.append(item)
                save(stored)
                return .success(())
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    /// Adds a previously removed item back.
    public func restore(_ item: LoginItem) -> Result<Void, Failure> {
        queue.sync {
            let escaped = Self.escape(item.path)
            switch run("tell application \"System Events\" to make login item at end with properties {path:\"\(escaped)\", hidden:false}") {
            case .success:
                save(disabledItems().filter { $0.path != item.path })
                return .success(())
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    // MARK: - Private

    static func parse(_ output: String) -> [LoginItem] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            return LoginItem(name: String(fields[0]), path: String(fields[1]))
        }
    }

    /// Escapes text for use inside an AppleScript string literal.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func run(_ source: String) -> Result<String, Failure> {
        guard let script = NSAppleScript(source: source) else { return .failure(.scriptFailed("invalid script")) }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error = error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -1743 { return .failure(.permissionDenied) }   // not authorized to send Apple events
            return .failure(.scriptFailed((error[NSAppleScript.errorMessage] as? String) ?? "error \(code)"))
        }
        return .success(descriptor.stringValue ?? "")
    }

    private func save(_ items: [LoginItem]) {
        guard let url = storeURL, let data = try? JSONEncoder().encode(items) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
