import Foundation
import ServiceManagement
import VPNShared

enum PrivilegedHelper {
    static var service: SMAppService { .daemon(plistName: VPNService.plistName) }
    static var isEnabled: Bool { service.status == .enabled }

    static var statusDescription: String {
        switch service.status {
        case .enabled: return "VPN access is enabled."
        case .requiresApproval: return "Approve ETHZ VPN in System Settings → General → Login Items & Extensions."
        case .notRegistered: return "Enable VPN access once to allow connections."
        case .notFound: return "VPN helper is missing. Install the complete signed app."
        @unknown default: return "VPN access is unavailable."
        }
    }

    static func enable(completion: @escaping (String?) -> Void) {
        do {
            _ = try Signing.teamID()
            guard Bundle.main.bundleURL.path == VPNService.installedApp else {
                throw VPNService.error("Install the app in /Applications using make install before enabling VPN access.")
            }
            if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                completion(statusDescription)
            } else if isEnabled {
                // Keep the legacy CLI available during side-by-side testing.
                completion(nil)
            } else { completion(statusDescription) }
        } catch { completion(error.localizedDescription) }
    }

    static func removeLegacyRules(completion: @escaping (String?) -> Void) {
        HelperClient.shared.call({ proxy, done in proxy.removeLegacyRules(reply: done) }) { (result: Result<String?, Error>) in
            switch result {
            case .success(let error): completion(error)
            case .failure(let error): completion(error.localizedDescription)
            }
        }
    }

    static func disable(completion: @escaping (String?) -> Void) {
        // Caller waits until the helper reports disconnected before unregistering it.
        HelperClient.shared.call({ proxy, done in proxy.status { done(($0, $2)) } }) { (result: Result<(String, String?), Error>) in
            switch result {
            case .success(let status) where status.0 == "disconnected":
                do { try service.unregister(); completion(nil) } catch { completion(error.localizedDescription) }
            case .success: completion("Disconnect the VPN and wait for it to stop before disabling VPN access.")
            case .failure(let error): completion(error.localizedDescription)
            }
        }
    }
}
