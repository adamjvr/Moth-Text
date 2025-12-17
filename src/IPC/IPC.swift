import Foundation

public enum IPC {
    public static func encodeEnvelope(_ env: IPCEnvelope) throws -> String {
        let data = try JSONCodec.encode(env)
        guard let s = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "IPC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to UTF-8 encode envelope"])
        }
        return s
    }

    public static func decodeEnvelope(fromLine line: String) throws -> IPCEnvelope {
        guard let data = line.data(using: .utf8) else {
            throw NSError(domain: "IPC", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to UTF-8 decode line"])
        }
        return try JSONCodec.decode(IPCEnvelope.self, from: data)
    }

    public static func makePingRequest(message: String) throws -> IPCEnvelope {
        let id = UUID().uuidString
        let paramsData = try JSONCodec.encode(PingParams(message: message))
        let params = try JSONCodec.decode(JSONValue.self, from: paramsData)
        return IPCEnvelope(id: id, type: .request, method: "core.ping", params: params)
    }

    public static func decodePingParams(_ value: JSONValue?) throws -> PingParams {
        guard let value else {
            throw NSError(domain: "IPC", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing params"])
        }
        let data = try JSONCodec.encode(value)
        return try JSONCodec.decode(PingParams.self, from: data)
    }

    public static func encodePingResult(_ result: PingResult) throws -> JSONValue {
        let data = try JSONCodec.encode(result)
        return try JSONCodec.decode(JSONValue.self, from: data)
    }

    public static func decodePingResult(_ value: JSONValue?) throws -> PingResult {
        guard let value else {
            throw NSError(domain: "IPC", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing result"])
        }
        let data = try JSONCodec.encode(value)
        return try JSONCodec.decode(PingResult.self, from: data)
    }
}
