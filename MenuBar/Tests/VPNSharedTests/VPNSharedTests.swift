import XCTest
@testable import VPNShared

final class VPNSharedTests: XCTestCase {
    func testCredentialsRejectConfigAndStdinInjection() {
        let valid = { (username: String, realm: String, password: String, token: String) in
            VPNService.validCredentials(username: username, realm: realm, password: password, token: token)
        }
        XCTAssertTrue(valid("student", "student-net", "p a$'ss", "JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(valid("--script=evil", "student-net", "password", "JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(valid("student", "realm\nscript=evil", "password", "JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(valid("student", "student-net", "answer\nsecond", "JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(valid("student", "student-net", "password", "JBSWY3DPEHPK3PXP\nscript=/tmp/evil"))
        XCTAssertFalse(valid("student", "student-net", "password", "JBSWY3DPEHPK3PXP\n"))
        XCTAssertFalse(valid("student", "student-net", "password\0", "JBSWY3DPEHPK3PXP"))
    }

    func testRouteCleanupRequiresExactHostIdentity() {
        let route = "destination: 192.0.2.5\ngateway: 192.0.2.1\ninterface: en0\nflags: <UP,GATEWAY,HOST,DONE,STATIC>\n"
        let identity = RouteIdentity(output: route)
        XCTAssertNotNil(identity)
        XCTAssertNil(RouteIdentity(output: route.replacingOccurrences(of: ",HOST", with: "")))
        XCTAssertNil(RouteIdentity(output: route.replacingOccurrences(of: "192.0.2.5", with: "default")))
        XCTAssertNotEqual(identity, RouteIdentity(output: route.replacingOccurrences(of: "en0", with: "en1")))
        XCTAssertNotEqual(identity, RouteIdentity(output: route.replacingOccurrences(of: "192.0.2.1", with: "192.0.2.2")))
        XCTAssertNil(RouteIdentity(output: "route: not found"))
    }
}
