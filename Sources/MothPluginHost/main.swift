// SPDX-License-Identifier: MPL-2.0
import Foundation
import MothIPC

let socketPath = "/tmp/mothtext.sock"

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

do {
    print("[MothPluginHost] Listening at \(socketPath)")
    let listener = try UnixDomainSocket.createServerListener(atPath: socketPath)

    print("[MothPluginHost] Waiting for a client...")
    let client = try listener.acceptClient()
    print("[MothPluginHost] Client connected")

    while true {
        let lines = try client.readAvailableLines()
        if lines.isEmpty {
            print("[MothPluginHost] Peer closed; exiting")
            break
        }

        for line in lines {
            let env = try IPC.decodeEnvelope(fromLine: line)
            print("[MothPluginHost] RX \(env.type.rawValue) \(env.method) id=\(env.id)")

            if env.type == .request && env.method == "core.ping" {
                let params = try IPC.decodePingParams(env.params)
                let result = PingResult(echoed: params.message, serverTimeISO8601: isoNow())

                let resp = IPCEnvelope(
                    id: env.id,
                    type: .response,
                    method: env.method,
                    params: nil,
                    result: try IPC.encodePingResult(result),
                    error: nil
                )

                try client.writeLine(try IPC.encodeEnvelope(resp))
                print("[MothPluginHost] TX response core.ping id=\(env.id)")
            } else if env.type == .request {
                let resp = IPCEnvelope(
                    id: env.id,
                    type: .response,
                    method: env.method,
                    params: nil,
                    result: nil,
                    error: IPCError(code: 404, message: "Unknown method: \(env.method)")
                )
                try client.writeLine(try IPC.encodeEnvelope(resp))
            }
        }
    }
} catch {
    FileHandle.standardError.write(Data("[MothPluginHost] ERROR: \(error)\n".utf8))
    exit(1)
}
