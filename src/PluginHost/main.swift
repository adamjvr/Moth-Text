import Foundation
import IPC

let socketPath = "/tmp/mothtext.sock"

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

do {
    print("[PluginHost] Listening at \(socketPath)")
    let listener = try UnixDomainSocket.createServerListener(atPath: socketPath)

    print("[PluginHost] Waiting for a client...")
    let client = try listener.acceptClient()
    print("[PluginHost] Client connected")

    while true {
        let lines = try client.readAvailableLines()
        if lines.isEmpty {
            print("[PluginHost] Peer closed; exiting")
            break
        }

        for line in lines {
            let env = try IPC.decodeEnvelope(fromLine: line)
            print("[PluginHost] RX \(env.type.rawValue) \(env.method) id=\(env.id)")

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
                print("[PluginHost] TX response core.ping id=\(env.id)")
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
    fputs("[PluginHost] ERROR: \(error)\n", stderr)
    exit(1)
}
