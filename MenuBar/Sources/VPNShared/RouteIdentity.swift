import Foundation
import Darwin

public struct RouteIdentity: Equatable {
    public let destination: String
    public let gateway: String
    public let interface: String

    public init?(output: String) {
        var fields: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        guard let destination = fields["destination"], let gateway = fields["gateway"],
              let interface = fields["interface"], !interface.isEmpty,
              let flags = fields["flags"], flags.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                .split(separator: ",").contains("HOST") else { return nil }
        var v4 = in_addr()
        var v6 = in6_addr()
        guard inet_pton(AF_INET, destination, &v4) == 1 || inet_pton(AF_INET6, destination, &v6) == 1 else { return nil }
        self.destination = destination
        self.gateway = gateway
        self.interface = interface
    }
}
