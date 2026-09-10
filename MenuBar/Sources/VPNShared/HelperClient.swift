import Foundation

public final class HelperClient {
    public static let shared = HelperClient()
    private init() {}

    // Each request has its own connection and a bounded, exactly-once completion.
    public func call<T>(_ operation: @escaping (VPNHelperProtocol, @escaping (T) -> Void) -> Void,
                        completion: @escaping (Result<T, Error>) -> Void) {
        do {
            let team = try Signing.teamID()
            let connection = NSXPCConnection(machServiceName: VPNService.helperID, options: .privileged)
            connection.setCodeSigningRequirement(Signing.requirement(team: team, identifiers: [VPNService.helperID]))
            connection.remoteObjectInterface = NSXPCInterface(with: VPNHelperProtocol.self)
            let lock = NSLock()
            var finished = false
            let finish: (Result<T, Error>) -> Void = { result in
                lock.lock()
                guard !finished else { lock.unlock(); return }
                finished = true
                lock.unlock()
                connection.invalidationHandler = nil
                connection.interruptionHandler = nil
                connection.invalidate()
                DispatchQueue.main.async { completion(result) }
            }
            connection.invalidationHandler = { finish(.failure(VPNService.error("VPN helper is unavailable. Enable it in VPN Access settings."))) }
            connection.interruptionHandler = { finish(.failure(VPNService.error("VPN helper connection was interrupted."))) }
            connection.resume()
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                finish(.failure(VPNService.error("VPN helper did not respond in time.")))
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ finish(.failure($0)) }) as? VPNHelperProtocol else {
                finish(.failure(VPNService.error("Cannot contact VPN helper.")))
                return
            }
            operation(proxy) { finish(.success($0)) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}
