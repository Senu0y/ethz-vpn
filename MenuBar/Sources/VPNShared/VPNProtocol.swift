import Foundation
import Security

public enum VPNService {
    public static let appID = "com.dcamenisch.ethz-vpn-menubar"
    public static let helperID = appID + ".helper"
    public static let cliID = appID + ".cli"
    public static let plistName = helperID + ".plist"
    public static let installedApp = "/Applications/ETHZ VPN.app"
    public static let runtimeApp = "/Library/Application Support/ETHZ VPN/Runtime.app"

    public static func error(_ message: String) -> NSError {
        NSError(domain: helperID, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // Secrets cannot introduce additional config directives or stdin answers.
    public static func validCredentials(username: String, realm: String, password: String, token: String) -> Bool {
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        return matches(username, "\\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\z")
            && matches(realm, "\\A[A-Za-z0-9][A-Za-z0-9-]{0,63}\\z")
            && !password.isEmpty && password.utf8.count <= 4096
            && !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && matches(token, "\\A[A-Za-z2-7]{8,256}={0,6}\\z")
    }
}

@objc public protocol VPNHelperProtocol {
    func connect(username: String, realm: String, password: String, token: String,
                 reply: @escaping (String?) -> Void)
    func disconnect(reply: @escaping (String?) -> Void)
    func status(reply: @escaping (String, String, String?) -> Void)
    func removeLegacyRules(reply: @escaping (String?) -> Void)
}

public enum Signing {
    // Derive the team from our own running, signed executable, never from client input.
    public static func teamID() throws -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            throw VPNService.error("Cannot inspect the application signature.")
        }
        var information: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "\\A[A-Z0-9]{10}\\z", options: .regularExpression) != nil else {
            throw VPNService.error("Sign the app and helper with an Apple Developer identity before enabling VPN access.")
        }
        return team
    }

    public static func requirement(team: String, identifiers: [String]) -> String {
        let ids = identifiers.map { "identifier \"\($0)\"" }.joined(separator: " or ")
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and (\(ids))"
    }
}
