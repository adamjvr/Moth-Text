// SPDX-License-Identifier: MPL-2.0
import Foundation
import MothApplication
import MothIPC

print(MothApplication.startupSummary(platform: "Linux"))

let socketPath = "/tmp/mothtext.sock"

do {
    print("[MothTextLinux] Connecting to \(socketPath)")
    let sock = try UnixDomainSocket.connect(toPath: socketPath)

    let req = try IPC.makePingRequest(message: "Hello from MothTextLinux (M0 repository foundation)")
    try sock.writeLine(try IPC.encodeEnvelope(req))
    print("[MothTextLinux] Sent ping id=\(req.id)")

    while true {
        let lines = try sock.readAvailableLines()
        if lines.isEmpty {
            print("[MothTextLinux] Host closed connection; exiting")
            break
        }
        for line in lines {
            let env = try IPC.decodeEnvelope(fromLine: line)
            if env.type == .response && env.method == "core.ping" && env.id == req.id {
                let pong = try IPC.decodePingResult(env.result)
                print("[MothTextLinux] Pong: echoed='\(pong.echoed)' serverTime='\(pong.serverTimeISO8601)'")
                exit(0)
            } else if env.type == .response && env.id == req.id, let err = env.error {
                print("[MothTextLinux] Error response: code=\(err.code) message=\(err.message)")
                exit(2)
            }
        }
    }
} catch {
    FileHandle.standardError.write(Data("[MothTextLinux] ERROR: \(error)\n".utf8))
    exit(1)
}
