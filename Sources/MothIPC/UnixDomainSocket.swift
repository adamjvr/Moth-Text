import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

public final class UnixDomainSocket {

    public enum Mode {
        case serverListener
        case connected
    }

    public let fd: Int32
    public let mode: Mode
    private var readBuffer = Data()

    init(fd: Int32, mode: Mode) {
        self.fd = fd
        self.mode = mode
    }

    deinit {
        #if os(Linux)
        _ = SwiftGlibc.close(fd)
        #else
        _ = Darwin.close(fd)
        #endif
    }

    // MARK: - Server

    public static func createServerListener(atPath path: String) throws -> UnixDomainSocket {
        #if os(Linux)
        _ = SwiftGlibc.unlink(path)
        let sock = SwiftGlibc.socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        _ = Darwin.unlink(path)
        let sock = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        #endif

        guard sock >= 0 else { throw NSError(domain: "UnixDomainSocket", code: 1) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { throw NSError(domain: "UnixDomainSocket", code: 2) }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            strncpy(raw, path, maxLen)
        }

        let bindResult: Int32 = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                #if os(Linux)
                SwiftGlibc.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                #else
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                #endif
            }
        }
        guard bindResult == 0 else { throw NSError(domain: "UnixDomainSocket", code: 3) }

        #if os(Linux)
        guard SwiftGlibc.listen(sock, 16) == 0 else { throw NSError(domain: "UnixDomainSocket", code: 4) }
        #else
        guard Darwin.listen(sock, 16) == 0 else { throw NSError(domain: "UnixDomainSocket", code: 4) }
        #endif

        return UnixDomainSocket(fd: sock, mode: .serverListener)
    }

    public func acceptClient() throws -> UnixDomainSocket {
        guard mode == .serverListener else { throw NSError(domain: "UnixDomainSocket", code: 5) }

        var addr = sockaddr()
        var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)

        #if os(Linux)
        let clientFD = SwiftGlibc.accept(fd, &addr, &len)
        #else
        let clientFD = Darwin.accept(fd, &addr, &len)
        #endif

        guard clientFD >= 0 else { throw NSError(domain: "UnixDomainSocket", code: 6) }

        return UnixDomainSocket(fd: clientFD, mode: .connected)
    }

    // MARK: - Client

    public static func connect(toPath path: String) throws -> UnixDomainSocket {
        #if os(Linux)
        let sock = SwiftGlibc.socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let sock = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        #endif

        guard sock >= 0 else { throw NSError(domain: "UnixDomainSocket", code: 7) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { throw NSError(domain: "UnixDomainSocket", code: 8) }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            strncpy(raw, path, maxLen)
        }

        let result: Int32 = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                #if os(Linux)
                SwiftGlibc.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                #else
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                #endif
            }
        }

        guard result == 0 else { throw NSError(domain: "UnixDomainSocket", code: 9) }

        return UnixDomainSocket(fd: sock, mode: .connected)
    }

    // MARK: - IO helpers (Phase 0)

    public func writeLine(_ line: String) throws {
        let out = line.hasSuffix("\n") ? line : (line + "\n")
        let bytes = Array(out.utf8)

        let sent: Int
        #if os(Linux)
        sent = bytes.withUnsafeBytes { SwiftGlibc.send(fd, $0.baseAddress, $0.count, 0) }
        #else
        sent = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        #endif

        guard sent == bytes.count else { throw NSError(domain: "UnixDomainSocket", code: 10) }
    }

    public func readAvailableLines() throws -> [String] {
        var buf = [UInt8](repeating: 0, count: 4096)

        let n: Int
        #if os(Linux)
        n = SwiftGlibc.recv(fd, &buf, buf.count, 0)
        #else
        n = Darwin.recv(fd, &buf, buf.count, 0)
        #endif

        if n <= 0 { return [] }

        readBuffer.append(contentsOf: buf[0..<n])

        var lines: [String] = []
        while let range = readBuffer.firstRange(of: Data([0x0A])) {
            let lineData = readBuffer.subdata(in: 0..<range.lowerBound)
            readBuffer.removeSubrange(0..<range.upperBound)
            if let s = String(data: lineData, encoding: .utf8) {
                lines.append(s)
            }
        }
        return lines
    }
}
