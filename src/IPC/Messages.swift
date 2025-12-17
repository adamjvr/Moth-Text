import Foundation

public enum IPCMessageType: String, Codable {
    case request
    case response
    case event
}

public struct IPCError: Codable {
    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct IPCEnvelope: Codable {
    public var id: String
    public var type: IPCMessageType
    public var method: String
    public var params: JSONValue?
    public var result: JSONValue?
    public var error: IPCError?

    public init(
        id: String,
        type: IPCMessageType,
        method: String,
        params: JSONValue? = nil,
        result: JSONValue? = nil,
        error: IPCError? = nil
    ) {
        self.id = id
        self.type = type
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
}

public struct PingParams: Codable {
    public var message: String
    public init(message: String) { self.message = message }
}

public struct PingResult: Codable {
    public var echoed: String
    public var serverTimeISO8601: String
    public init(echoed: String, serverTimeISO8601: String) {
        self.echoed = echoed
        self.serverTimeISO8601 = serverTimeISO8601
    }
}
