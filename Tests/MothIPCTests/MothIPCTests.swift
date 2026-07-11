// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import MothIPC

final class MothIPCTests: XCTestCase {
    func testPingEnvelopeRoundTrip() throws {
        let request = try IPC.makePingRequest(message: "hello")
        let encoded = try IPC.encodeEnvelope(request)
        let decoded = try IPC.decodeEnvelope(fromLine: encoded)
        XCTAssertEqual(decoded.id, request.id)
        XCTAssertEqual(decoded.method, "core.ping")
    }
}
