//
//  AppSupport.swift
//  MacControlCore
//

import Foundation

/// Location of MacControl's private data (history, event log).
public enum AppSupport {

    /// `~/Library/Application Support/MacControl`
    public static var directory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MacControl", isDirectory: true)
    }
}
