import Foundation
import Network
import Darwin

/// The part of the network path that must remain stable underneath OpenConnect.
/// A VPN may replace the system default route, so this deliberately records the
/// Wi-Fi interface's address and scoped default gateway instead.
struct PhysicalNetworkSnapshot: Equatable {
    let interfaceName: String
    let ipv4Address: String
    let gateway: String

    static func capture(preferredInterface: String? = nil) -> PhysicalNetworkSnapshot? {
        let routes = physicalDefaultRoutes()
        let interfaceName = preferredInterface
            ?? routes.first(where: { !$0.interfaceName.hasPrefix("utun") })?.interfaceName

        guard let interfaceName,
              let address = ipv4Address(for: interfaceName)
        else { return nil }

        let gateway = routes.first(where: { $0.interfaceName == interfaceName })?.gateway ?? ""
        return PhysicalNetworkSnapshot(
            interfaceName: interfaceName,
            ipv4Address: address,
            gateway: gateway
        )
    }

    private static func ipv4Address(for interfaceName: String) -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }

        var cursor = addresses
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            guard String(cString: interface.pointee.ifa_name) == interfaceName,
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == AF_INET
            else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            return String(cString: hostname)
        }
        return nil
    }

    private static func physicalDefaultRoutes() -> [(interfaceName: String, gateway: String)] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-rn", "-f", "inet"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap { line in
            let columns = line.split(whereSeparator: { $0.isWhitespace })
            guard columns.count >= 4, columns[0] == "default" else { return nil }
            return (interfaceName: String(columns[3]), gateway: String(columns[1]))
        }
    }
}

/// Emits a settled snapshot after Wi-Fi path changes. Network.framework is the
/// trigger; the snapshot comparison prevents VPN route changes from being
/// mistaken for a physical WLAN switch.
final class PhysicalNetworkMonitor {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "com.dcamenisch.eth-vpn.network-monitor")
    private var pendingUpdate: DispatchWorkItem?
    private var handler: ((PhysicalNetworkSnapshot?) -> Void)?

    private(set) var currentSnapshot: PhysicalNetworkSnapshot?

    func start(handler: @escaping (PhysicalNetworkSnapshot?) -> Void) {
        self.handler = handler
        monitor.pathUpdateHandler = { [weak self] path in
            self?.scheduleUpdate(for: path)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func scheduleUpdate(for path: NWPath) {
        pendingUpdate?.cancel()
        let interfaceName = path.availableInterfaces.first(where: { $0.type == .wifi })?.name
        let isSatisfied = path.status == .satisfied
        let update = DispatchWorkItem { [weak self] in
            let snapshot = isSatisfied
                ? PhysicalNetworkSnapshot.capture(preferredInterface: interfaceName)
                : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.currentSnapshot = snapshot
                self.handler?(snapshot)
            }
        }
        pendingUpdate = update
        queue.asyncAfter(deadline: .now() + 2, execute: update)
    }
}
