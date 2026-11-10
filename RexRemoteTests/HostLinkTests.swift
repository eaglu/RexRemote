import XCTest
@testable import RexRemote

final class HostLinkTests: XCTestCase {
    func testPlainTailnetAddress() {
        XCTAssertEqual(
            HostLink.address(from: "rex-abc.tail1234.ts.net") ?? "",
            "rex-abc.tail1234.ts.net"
        )
    }

    func testHTTPSLinkKeepsItsScheme() {
        XCTAssertEqual(
            HostLink.address(from: "https://rex-abc.tail1234.ts.net") ?? "",
            "https://rex-abc.tail1234.ts.net"
        )
    }

    func testTrailingSlashAndPathAreDropped() {
        XCTAssertEqual(
            HostLink.address(from: "https://rex-abc.tail1234.ts.net/") ?? "",
            "https://rex-abc.tail1234.ts.net"
        )
        XCTAssertEqual(
            HostLink.address(from: "http://192.168.100.55:7297/api/control") ?? "",
            "http://192.168.100.55:7297"
        )
    }

    func testLANAddressWithPort() {
        XCTAssertEqual(HostLink.address(from: "192.168.100.55:7297") ?? "", "192.168.100.55:7297")
    }

    func testJSONPayloadFromPairJSON() {
        let payload = #"{"address":"https://rex-abc.tail1234.ts.net"}"#
        XCTAssertEqual(
            HostLink.address(from: payload) ?? "",
            "https://rex-abc.tail1234.ts.net"
        )
    }

    func testSurroundingQuotesAndNewlinesAreTrimmed() {
        XCTAssertEqual(HostLink.address(from: "  \"rex-abc.ts.net\"\n") ?? "", "rex-abc.ts.net")
    }

    func testRejectsJunk() {
        XCTAssertNil(HostLink.address(from: ""))
        XCTAssertNil(HostLink.address(from: "   "))
        XCTAssertNil(HostLink.address(from: "hello there"))
        XCTAssertNil(HostLink.address(from: "ftp://example.com"))
        XCTAssertNil(HostLink.address(from: "192.168.100.55:99999"))
        XCTAssertNil(HostLink.address(from: "https://"))
    }
}

final class HostHandshakeTests: XCTestCase {
    func testBearerTokenBecomesAuthorizationHeader() {
        var host = HostConfig(name: "x", address: "rex.example.com")
        host.token = "abc123"
        XCTAssertEqual(host.handshakeHeaders.map(\.name), ["Authorization"])
        XCTAssertEqual(host.handshakeHeaders.first?.value, "Bearer abc123")
    }

    func testAccessTokenAddsCloudflareHeaders() {
        var host = HostConfig(name: "x", address: "https://rex.430904.site")
        host.accessClientID = "id.access"
        host.accessClientSecret = "secret-value"
        XCTAssertTrue(host.usesAccessToken)
        let names = host.handshakeHeaders.map(\.name)
        XCTAssertEqual(names, ["CF-Access-Client-Id", "CF-Access-Client-Secret"])
        XCTAssertEqual(host.handshakeHeaders.last?.value, "secret-value")
    }

    func testHalfAnAccessTokenSendsNothing() {
        var host = HostConfig(name: "x", address: "https://rex.430904.site")
        host.accessClientID = "id.access"
        XCTAssertFalse(host.usesAccessToken)
        XCTAssertTrue(host.handshakeHeaders.isEmpty)
    }

    func testTunnelAddressStaysHTTPS() throws {
        let host = HostConfig(name: "x", address: "rex.430904.site")
        XCTAssertEqual(try host.controlURL().absoluteString, "wss://rex.430904.site/api/control")
        XCTAssertEqual(try host.dataURL().absoluteString, "wss://rex.430904.site/api/data")
    }
}
