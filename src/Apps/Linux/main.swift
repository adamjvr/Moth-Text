import Foundation
import IPC

let socketPath = "/tmp/mothtext.sock"

do {
    print("[LinuxApp] Connecting to \(socketPath)")
    let sock = try UnixDomainSocket.connect(toPath: socketPath)

    let req = try IPC.makePingRequest(message: "Hello from LinuxApp (Phase 0, src layout)")
    try sock.writeLine(try IPC.encodeEnvelope(req))
    print("[LinuxApp] Sent ping id=\(req.id)")

    while true {
        let lines = try sock.readAvailableLines()
        if lines.isEmpty {
            print("[LinuxApp] Host closed connection; exiting")
            break
        }
        for line in lines {
            let env = try IPC.decodeEnvelope(fromLine: line)
            if env.type == .response && env.method == "core.ping" && env.id == req.id {
                let pong = try IPC.decodePingResult(env.result)
                print("[LinuxApp] Pong: echoed='\(pong.echoed)' serverTime='\(pong.serverTimeISO8601)'")
                exit(0)
            } else if env.type == .response && env.id == req.id, let err = env.error {
                print("[LinuxApp] Error response: code=\(err.code) message=\(err.message)")
                exit(2)
            }
        }
    }
} catch {
    fputs("[LinuxApp] ERROR: \(error)\n", stderr)
    exit(1)
}
