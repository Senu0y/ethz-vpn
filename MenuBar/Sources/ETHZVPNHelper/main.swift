import Foundation
import Darwin
import SystemConfiguration
import Security
import OSLog
import VPNShared

private let helperLog = Logger(subsystem: VPNService.helperID, category: "helper")

// All state and process lifecycle operations run on this serial queue.
final class VPNDaemon {
    let queue = DispatchQueue(label: "ethz-vpn.helper")
    private var process: Process?
    private var owner: uid_t?
    private var session: URL?
    private var stopping = false
    private var lastError: String?
    private let routeRecord = URL(fileURLWithPath: "/private/var/run/ethz-vpn.route")

    private func authorize(_ uid: uid_t) throws {
        var consoleUID: uid_t = 0
        _ = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil)
        guard uid != 0, uid == consoleUID else {
            throw VPNService.error("Only the currently logged-in desktop user can control this VPN.")
        }
        guard owner == nil || owner == uid else {
            throw VPNService.error("This VPN session belongs to another user.")
        }
    }

    private func trustedBundle() throws -> URL {
        let app = URL(fileURLWithPath: VPNService.runtimeApp)
        // Root-owned, non-writable resources prevent replacement between validation and exec.
        // Do not run privileged binaries or scripts from ~/Applications or Homebrew.
        guard let entries = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
            throw VPNService.error("Install the signed app in /Applications using make install.")
        }
        // /Applications is admin-writable. The execution copy lives under a protected
        // parent so the entire bundle cannot be swapped after checking its signature.
        var parent = app.deletingLastPathComponent()
        while parent.path != "/" {
            let attributes = try FileManager.default.attributesOfItem(atPath: parent.path)
            guard parent.resolvingSymlinksInPath().path == parent.path,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
                  let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else {
                throw VPNService.error("The VPN runtime parent directory is not protected. Reinstall with make install.")
            }
            parent.deleteLastPathComponent()
        }
        let urls = [app] + entries.compactMap { $0 as? URL }
        for url in urls {
            let resolved = url.resolvingSymlinksInPath()
            guard resolved.path == app.path || resolved.path.hasPrefix(app.path + "/") else {
                throw VPNService.error("The app contains an external symbolic link.")
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
            guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
                  let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else {
                throw VPNService.error("The app must be owned by root and not writable by other users. Reinstall with make install.")
            }
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let expression = Signing.requirement(team: try Signing.teamID(), identifiers: [VPNService.appID])
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw VPNService.error("The installed app signature is invalid. Reinstall the signed app.")
        }
        return app
    }

    func connect(uid: uid_t, username: String, realm: String, password: String, token: String) throws {
        try authorize(uid)
        guard process == nil else { throw VPNService.error("A VPN session is already active.") }
        guard VPNService.validCredentials(username: username, realm: realm, password: password, token: token) else {
            throw VPNService.error("Invalid username, realm, password, or base32 OTP secret.")
        }
        let app = try trustedBundle()
        helperLog.notice("Connection requested")
        cleanupRecordedRoute(context: "before connection")
        let resources = app.appendingPathComponent("Contents/Resources")
        var template = Array("/private/var/run/ethz-vpn.XXXXXX".utf8CString)
        guard let directory = mkdtemp(&template) else { throw VPNService.error("Cannot create private VPN session directory.") }
        let session = URL(fileURLWithPath: String(cString: directory))
        let config = session.appendingPathComponent("token.conf")
        do {
            try Data("token-mode=totp\ntoken-secret=sha1:base32:\(token)\n".utf8).write(to: config)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
            let child = Process()
            child.executableURL = resources.appendingPathComponent("openconnect")
            // OpenConnect interprets --script using a shell. This is a fixed, quoted bundle path.
            child.arguments = ["-u", "\(username)@\(realm).ethz.ch", "-g", realm,
                               "--useragent=AnyConnect", "--passwd-on-stdin", "--config", config.path,
                               "--script", "'\(resources.path)/vpn-script'", "--no-external-auth", "sslvpn.ethz.ch"]
            child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/root",
                                 "LANG": "C", "ETHZ_VPN_SESSION_DIR": session.path,
                                 "ETHZ_VPN_ROUTE_RECORD": routeRecord.path]
            child.currentDirectoryURL = session
            let input = Pipe()
            child.standardInput = input
            child.standardOutput = FileHandle.nullDevice
            // Never retain authentication output, cookies, or server banners in logs.
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] child in
                self?.queue.async { [weak self] in
                    guard let self, self.process === child else { return }
                    if child.terminationStatus != 0 && !self.stopping {
                        let category = (try? String(contentsOf: session.appendingPathComponent("network-error"), encoding: .utf8))?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if category == "address-not-available" {
                            self.lastError = "Network setup failed because macOS could not use the route to the VPN server. A stale host route may be responsible; retry the connection."
                        } else {
                            self.lastError = "OpenConnect exited with status \(child.terminationStatus). Check your credentials and network."
                        }
                        helperLog.error("OpenConnect exited unexpectedly; status=\(child.terminationStatus, privacy: .public), network_category=\(category ?? "none", privacy: .public)")
                    } else {
                        helperLog.notice("OpenConnect stopped; requested=\(self.stopping, privacy: .public), status=\(child.terminationStatus, privacy: .public)")
                    }
                    self.cleanupRecordedRoute(context: "after connection")
                    try? FileManager.default.removeItem(at: session)
                    self.process = nil
                    self.session = nil
                    self.owner = nil
                    self.stopping = false
                }
            }
            try child.run()
            helperLog.notice("OpenConnect started; pid=\(child.processIdentifier, privacy: .public)")
            self.process = child
            self.owner = uid
            self.session = session
            self.stopping = false
            self.lastError = nil
            input.fileHandleForWriting.write(Data((password + "\n").utf8))
            input.fileHandleForWriting.closeFile()
        } catch {
            helperLog.error("Connection setup failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: session)
            throw error
        }
    }

    func disconnect(uid: uid_t) throws {
        try authorize(uid)
        guard let child = process else { return }
        helperLog.notice("Disconnect requested")
        stopping = true
        // Process owns this exact child; never search for or signal unrelated OpenConnect sessions.
        child.interrupt()
        queue.asyncAfter(deadline: .now() + 6) { [weak self, weak child] in
            guard let self, let child, self.process === child, child.isRunning else { return }
            child.terminate()
            self.queue.asyncAfter(deadline: .now() + 3) { [weak self, weak child] in
                guard let self, let child, self.process === child, child.isRunning else { return }
                kill(child.processIdentifier, SIGKILL)
            }
        }
    }

    func status(uid: uid_t) throws -> (String, String, String?) {
        try authorize(uid)
        guard process != nil else { return ("disconnected", "", lastError) }
        if stopping { return ("disconnecting", "", nil) }
        let ip = session.flatMap { try? String(contentsOf: $0.appendingPathComponent("ip"), encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (ip.isEmpty ? "connecting" : "connected", ip, nil)
    }

    func removeLegacyRules(uid: uid_t) throws {
        try authorize(uid)
        // Dedicated files from previous releases; never accept a path from an XPC client.
        for path in ["/etc/sudoers.d/ethz-vpn", "/etc/sudoers.d/eth-vpn"] {
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        }
    }

    private func cleanupRecordedRoute(context: String) {
        // The network script stores only a route created by this app. Keep the record
        // until exact-match deletion succeeds so a later attempt can recover after a
        // helper interruption, DHCP renewal, or sleep/wake transition.
        guard FileManager.default.fileExists(atPath: routeRecord.path) else {
            helperLog.debug("No owned server route to clean up; context=\(context, privacy: .public)")
            return
        }
        guard let saved = try? String(contentsOf: routeRecord, encoding: .utf8),
              let identity = RouteIdentity(output: saved) else {
            helperLog.error("Discarding invalid owned-route record; context=\(context, privacy: .public)")
            try? FileManager.default.removeItem(at: routeRecord)
            return
        }
        let query = Process()
        query.executableURL = URL(fileURLWithPath: "/sbin/route")
        query.arguments = ["-n", "get", identity.destination]
        let output = Pipe()
        query.standardOutput = output
        query.standardError = FileHandle.nullDevice
        guard (try? query.run()) != nil else {
            helperLog.error("Could not inspect owned server route; context=\(context, privacy: .public)")
            return
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        query.waitUntilExit()
        guard query.terminationStatus == 0 else {
            helperLog.error("Owned server route lookup failed; context=\(context, privacy: .public), status=\(query.terminationStatus, privacy: .public)")
            return
        }
        guard let current = RouteIdentity(output: String(decoding: data, as: UTF8.self)) else {
            helperLog.notice("Owned server host route is already absent; context=\(context, privacy: .public)")
            try? FileManager.default.removeItem(at: routeRecord)
            return
        }
        guard current == identity else {
            helperLog.notice("Owned server route changed externally; leaving current route untouched; context=\(context, privacy: .public)")
            try? FileManager.default.removeItem(at: routeRecord)
            return
        }
        let deletion = Process()
        deletion.executableURL = URL(fileURLWithPath: "/sbin/route")
        deletion.arguments = ["-n", "delete", "-host", identity.destination]
        deletion.standardOutput = FileHandle.nullDevice
        deletion.standardError = FileHandle.nullDevice
        guard (try? deletion.run()) != nil else {
            helperLog.error("Could not start owned server route deletion; context=\(context, privacy: .public)")
            return
        }
        deletion.waitUntilExit()
        if deletion.terminationStatus == 0 {
            helperLog.notice("Deleted owned server host route; context=\(context, privacy: .public)")
            try? FileManager.default.removeItem(at: routeRecord)
        } else {
            helperLog.error("Owned server route deletion failed; context=\(context, privacy: .public), status=\(deletion.terminationStatus, privacy: .public)")
        }
    }
}

final class ClientSession: NSObject, VPNHelperProtocol {
    let daemon: VPNDaemon
    let uid: uid_t
    init(daemon: VPNDaemon, uid: uid_t) { self.daemon = daemon; self.uid = uid }
    private func perform(_ reply: @escaping (String?) -> Void, _ work: @escaping () throws -> Void) {
        daemon.queue.async {
            do { try work(); reply(nil) } catch { reply(error.localizedDescription) }
        }
    }
    func connect(username: String, realm: String, password: String, token: String, reply: @escaping (String?) -> Void) {
        perform(reply) { try self.daemon.connect(uid: self.uid, username: username, realm: realm, password: password, token: token) }
    }
    func disconnect(reply: @escaping (String?) -> Void) {
        perform(reply) { try self.daemon.disconnect(uid: self.uid) }
    }
    func status(reply: @escaping (String, String, String?) -> Void) {
        daemon.queue.async {
            do { let value = try self.daemon.status(uid: self.uid); reply(value.0, value.1, value.2) }
            catch { reply("unavailable", "", error.localizedDescription) }
        }
    }
    func removeLegacyRules(reply: @escaping (String?) -> Void) {
        perform(reply) { try self.daemon.removeLegacyRules(uid: self.uid) }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let daemon = VPNDaemon()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else {
            helperLog.error("Rejected root XPC client")
            return false
        }
        helperLog.debug("Accepted XPC client")
        connection.exportedInterface = NSXPCInterface(with: VPNHelperProtocol.self)
        connection.exportedObject = ClientSession(daemon: daemon, uid: connection.effectiveUserIdentifier)
        connection.resume()
        return true
    }
}

do {
    guard geteuid() == 0 else { throw VPNService.error("This helper must be started by macOS Service Management.") }
    helperLog.notice("VPN helper starting")
    let team = try Signing.teamID()
    let listener = NSXPCListener(machServiceName: VPNService.helperID)
    listener.setConnectionCodeSigningRequirement(Signing.requirement(team: team, identifiers: [VPNService.appID, VPNService.cliID]))
    let delegate = ListenerDelegate()
    listener.delegate = delegate
    listener.resume()
    withExtendedLifetime(delegate) { RunLoop.main.run() }
} catch {
    helperLog.fault("VPN helper startup failed: \(error.localizedDescription, privacy: .public)")
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
