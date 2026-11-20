//
//  SigningTrust.swift
//  MacControlCore
//

import Foundation

/// What the app and the helper trust to recognise each other.
///
/// Both modes pin the *identity of the signer*, never just a name, so a stranger's binary cannot talk to the helper:
/// - `team`: an Apple-issued certificate (Apple Development / Developer ID) of one Team ID.
/// - `certificate`: one specific certificate, identified by its SHA-1 hash. This is how a personal, self-signed
///   code-signing certificate from Keychain Access is trusted, with no Apple account or Xcode involved.
public enum SigningTrust: Equatable {
    case team(String)
    case certificate(sha1: String)

    /// Info.plist keys written by `build.sh`.
    public static let teamKey = HelperConstants.teamIDKey
    public static let certificateKey = "MCSigningCertHash"

    /// Reads the trust from an Info.plist dictionary. A team ID wins over a certificate hash. Malformed values are ignored.
    public init?(infoDictionary: [String: Any]?) {
        if let team = infoDictionary?[Self.teamKey] as? String,
           team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil {
            self = .team(team)
        } else if let hash = infoDictionary?[Self.certificateKey] as? String,
                  hash.range(of: #"^[0-9A-Fa-f]{40}$"#, options: .regularExpression) != nil {
            self = .certificate(sha1: hash.uppercased())
        } else {
            return nil
        }
    }

    /// The trust configured in the running executable's (possibly embedded) Info.plist.
    public static var current: SigningTrust? {
        SigningTrust(infoDictionary: [
            teamKey: Bundle.main.object(forInfoDictionaryKey: teamKey) as Any,
            certificateKey: Bundle.main.object(forInfoDictionaryKey: certificateKey) as Any
        ])
    }

    /// Requirement the helper imposes on its client (the app).
    public var clientRequirement: String {
        requirement(identifier: HelperConstants.appBundleIdentifier)
    }

    /// Requirement the app imposes on the helper it talks to.
    public var helperRequirement: String {
        requirement(identifier: HelperConstants.machServiceName)
    }

    private func requirement(identifier: String) -> String {
        switch self {
        case .team(let id):
            return #"anchor apple generic and identifier "\#(identifier)" and certificate leaf[subject.OU] = "\#(id)""#
        case .certificate(let hash):
            return #"identifier "\#(identifier)" and certificate leaf = H"\#(hash)""#
        }
    }
}
