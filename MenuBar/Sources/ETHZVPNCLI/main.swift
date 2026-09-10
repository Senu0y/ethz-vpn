import Foundation
import VPNShared

func fail(_ message: String) -> Never {
    fputs("ETHZ VPN: \(message)\n", stderr)
    exit(1)
}

func waitForState(_ desired: String, deadline: Date) {
    HelperClient.shared.call({ proxy, done in proxy.status { done(($0, $1, $2)) } }) {
        (result: Result<(String, String, String?), Error>) in
        switch result {
        case .failure(let error): fail(error.localizedDescription)
        case .success(let status):
            if status.0 == desired {
                print(status.1.isEmpty ? desired : "\(desired): \(status.1)")
                exit(0)
            }
            if let error = status.2 { fail(error) }
            if Date() >= deadline { fail("Timed out waiting for VPN to become \(desired). Check status before retrying.") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { waitForState(desired, deadline: deadline) }
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("Use connect <username> <realm>, disconnect, or status.") }
switch command {
case "connect":
    guard arguments.count == 3, let password = readLine(), let token = readLine(),
          VPNService.validCredentials(username: arguments[1], realm: arguments[2], password: password, token: token) else {
        fail("Provide username and realm as arguments, and password and base32 OTP secret on two stdin lines.")
    }
    HelperClient.shared.call({ proxy, done in
        proxy.connect(username: arguments[1], realm: arguments[2], password: password, token: token, reply: done)
    }) { (result: Result<String?, Error>) in
        switch result {
        case .failure(let error): fail(error.localizedDescription)
        case .success(let error):
            if let error { fail(error) }
            waitForState("connected", deadline: Date().addingTimeInterval(90))
        }
    }
case "disconnect":
    HelperClient.shared.call({ proxy, done in proxy.disconnect(reply: done) }) { (result: Result<String?, Error>) in
        switch result {
        case .failure(let error): fail(error.localizedDescription)
        case .success(let error):
            if let error { fail(error) }
            waitForState("disconnected", deadline: Date().addingTimeInterval(20))
        }
    }
case "status":
    HelperClient.shared.call({ proxy, done in proxy.status { done(($0, $1, $2)) } }) { (result: Result<(String, String, String?), Error>) in
        switch result {
        case .failure(let error): fail(error.localizedDescription)
        case .success(let status):
            if status.0 == "unavailable" { fail(status.2 ?? "VPN helper is unavailable.") }
            print(status.1.isEmpty ? status.0 : "\(status.0): \(status.1)")
            if let error = status.2 { fputs("\(error)\n", stderr) }
            exit(0)
        }
    }
default: fail("Unknown command.")
}
RunLoop.main.run()
