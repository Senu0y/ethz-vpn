import Foundation
import VPNShared
import SystemConfiguration
import AppKit
import UserNotifications

enum VPNState {
    case connected(ip: String)
    case connecting
    case disconnected
    case disconnecting

    var isConnected: Bool    { if case .connected    = self { return true }; return false }
    var isTransitioning: Bool { if case .connecting  = self { return true }
                                if case .disconnecting = self { return true }; return false }
}

// MARK: - App-wide constants
enum AppConstants {
    static let appName        = "ETH VPN"
    static let defaultRealm   = "student-net"
}

final class VPNController {
    static let shared = VPNController()
    private(set) var state: VPNState = .disconnected
    private var statusTimer: Timer?
    private var polling = false
    private var requestPending = false
    private var revision = 0
    private var lastReportedError: String?
    private var connectionProfile: VPNProfile?
    private var reconnectProfile: VPNProfile?
    private var networkSnapshot: String?
    var onStateChange: ((VPNState) -> Void)?

    private init() { startPolling() }

    func connect(profile: VPNProfile? = nil) {
        guard case .disconnected = state, !requestPending else { return }
        guard PrivilegedHelper.isEnabled else {
            NotificationCenter.default.post(name: .vpnSecretsNotFound, object: nil)
            return
        }
        let store = ProfileStore.shared
        guard let target = profile ?? store.activeProfile,
              let password = store.password(for: target), let token = store.token(for: target) else {
            NotificationCenter.default.post(name: .vpnSecretsNotFound, object: nil)
            return
        }
        guard VPNService.validCredentials(username: target.username, realm: target.realm, password: password, token: token) else {
            postNotification(body: "Check the profile username, realm, password, and base32 OTP secret.")
            return
        }
        store.activeProfileID = target.id
        connectionProfile = target
        networkSnapshot = physicalNetworkSnapshot()
        revision += 1
        requestPending = true
        lastReportedError = nil
        setState(.connecting)
        HelperClient.shared.call({ proxy, done in
            proxy.connect(username: target.username, realm: target.realm, password: password, token: token, reply: done)
        }) { (result: Result<String?, Error>) in
            self.requestPending = false
            if let error = self.errorMessage(result) {
                self.setState(.disconnected)
                self.postNotification(body: error)
            }
            self.pollStatus()
        }
    }

    func toggleConnection() {
        switch state {
        case .disconnected: connect()
        case .connected: disconnect()
        default: break
        }
    }

    func disconnect() {
        reconnectProfile = nil
        stopSession()
    }

    private func stopSession() {
        guard !requestPending, state.isConnected || state.isTransitioning else { return }
        if case .disconnecting = state { return }
        revision += 1
        requestPending = true
        setState(.disconnecting)
        HelperClient.shared.call({ proxy, done in proxy.disconnect(reply: done) }) { (result: Result<String?, Error>) in
            self.requestPending = false
            if let error = self.errorMessage(result) { self.postNotification(body: error) }
            self.pollStatus()
        }
    }

    func startPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pollStatus() }
        pollStatus()
    }

    private func pollStatus() {
        guard PrivilegedHelper.isEnabled, !polling, !requestPending else { return }
        polling = true
        let expectedRevision = revision
        HelperClient.shared.call({ proxy, done in proxy.status { done(($0, $1, $2)) } }) {
            (result: Result<(String, String, String?), Error>) in
            self.polling = false
            guard self.revision == expectedRevision, !self.requestPending else { return }
            switch result {
            case .success(let status):
                switch status.0 {
                case "connected": self.setState(.connected(ip: status.1))
                case "connecting": self.setState(.connecting)
                case "disconnecting": self.setState(.disconnecting)
                default: self.setState(.disconnected)
                }
                if let error = status.2, error != self.lastReportedError {
                    self.lastReportedError = error
                    self.postNotification(body: error)
                }
                if status.0 == "disconnected", let profile = self.reconnectProfile {
                    self.reconnectProfile = nil
                    self.connect(profile: profile)
                } else if status.0 == "disconnected" {
                    self.connectionProfile = nil
                } else if status.0 == "connected" || status.0 == "connecting", let profile = self.connectionProfile {
                    let current = self.physicalNetworkSnapshot()
                    if let previous = self.networkSnapshot, let current, current != previous {
                        self.networkSnapshot = current
                        self.reconnectProfile = profile
                        self.stopSession()
                    }
                    if self.networkSnapshot == nil { self.networkSnapshot = current }
                }
            case .failure(let error):
                self.setState(.disconnected)
                if error.localizedDescription != self.lastReportedError {
                    self.lastReportedError = error.localizedDescription
                    self.postNotification(body: error.localizedDescription)
                }
            }
        }
    }

    private func errorMessage(_ result: Result<String?, Error>) -> String? {
        switch result {
        case .success(let error): return error
        case .failure(let error): return error.localizedDescription
        }
    }

    private func physicalNetworkSnapshot() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "ETHZ VPN" as CFString, nil, nil),
              let values = SCDynamicStoreCopyMultiple(store, nil,
                  ["State:/Network/Interface/en[0-9]+/IPv4"] as CFArray) as? [String: [String: Any]],
              !values.isEmpty else { return nil }
        // Physical interface addresses and routers change across Wi-Fi networks;
        // tunnel/default-route changes do not trigger this comparison.
        return values.keys.sorted().map { key in
            let data = values[key] ?? [:]
            let addresses = (data["Addresses"] as? [String] ?? []).sorted().joined(separator: ",")
            return key + ":" + addresses + ":" + (data["Router"] as? String ?? "")
        }.joined(separator: "|")
    }

    private func setState(_ newState: VPNState) {
        state = newState
        onStateChange?(newState)
    }

    func isOpenconnectRunning() -> Bool { state.isConnected || state.isTransitioning }

    func postNotification(body: String) {
        let content = UNMutableNotificationContent()
        content.title = AppConstants.appName
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

extension Notification.Name {
    static let vpnSecretsNotFound = Notification.Name("com.dcamenisch.ethz-vpn.secretsNotFound")
}
