// SPDX-License-Identifier: MPL-2.0
import Foundation
import MothApplication
import MothIPC

private let socketPath = "/tmp/mothtext.sock"

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func runPluginHostPingSmokeTest() throws {
    print("[MothTextLinux] Connecting to optional plugin host at \(socketPath)")
    let socket = try UnixDomainSocket.connect(toPath: socketPath)

    let request = try IPC.makePingRequest(
        message: "Hello from MothTextLinux IPC smoke test"
    )
    try socket.writeLine(try IPC.encodeEnvelope(request))
    print("[MothTextLinux] Sent ping id=\(request.id)")

    while true {
        let lines = try socket.readAvailableLines()
        if lines.isEmpty {
            throw NSError(
                domain: "MothTextLinux.IPCSmokeTest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Plugin host closed before replying"]
            )
        }

        for line in lines {
            let envelope = try IPC.decodeEnvelope(fromLine: line)
            guard envelope.id == request.id else { continue }

            if let error = envelope.error {
                throw NSError(
                    domain: "MothTextLinux.IPCSmokeTest",
                    code: error.code,
                    userInfo: [NSLocalizedDescriptionKey: error.message]
                )
            }

            guard envelope.type == .response, envelope.method == "core.ping" else {
                continue
            }

            let pong = try IPC.decodePingResult(envelope.result)
            print("[MothTextLinux] Plugin host pong: '\(pong.echoed)'")
            return
        }
    }
}

print(MothApplication.startupSummary(platform: "Linux"))

if CommandLine.arguments.contains("--ipc-smoke") {
    do {
        try runPluginHostPingSmokeTest()
        print("[MothTextLinux] IPC smoke test passed")
        exit(EXIT_SUCCESS)
    } catch {
        writeError("[MothTextLinux] IPC smoke test failed: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}

// Normal application startup must not depend on the optional plugin host.
// Phase M0 still exposes a terminal proof shell; a Luna-rendered Moth window is
// introduced by the paired Luna 5E / Moth M1 application integration work.
print("[MothTextLinux] Core application bootstrap passed")
print("[MothTextLinux] Plugin services are optional; use --ipc-smoke to test them")
