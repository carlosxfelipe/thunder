//
//  MCPModels.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 22/05/26.
//

import Foundation

/// Represents the JSON-RPC protocol version required by MCP
let JSON_RPC_VERSION = "2.0"

/// Represents the message ID, can be String or Int
public enum MCPID: Codable, Hashable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            throw DecodingError.typeMismatch(MCPID.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Int for MCPID"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        }
    }
}

/// Base MCP Request (JSON-RPC)
public struct MCPRequest: Codable {
    public let jsonrpc: String
    public let method: String
    public let params: [String: AnyCodable]?
    public let id: MCPID

    public init(method: String, params: [String: AnyCodable]?, id: MCPID) {
        jsonrpc = JSON_RPC_VERSION
        self.method = method
        self.params = params
        self.id = id
    }
}

/// Base MCP Notification (without ID)
public struct MCPNotification: Codable {
    public let jsonrpc: String
    public let method: String
    public let params: [String: AnyCodable]?

    public init(method: String, params: [String: AnyCodable]?) {
        jsonrpc = JSON_RPC_VERSION
        self.method = method
        self.params = params
    }
}

/// Base MCP Response
public struct MCPResponse: Codable {
    public let jsonrpc: String
    public let id: MCPID
    public let result: AnyCodable?
    public let error: MCPError?

    public init(id: MCPID, result: AnyCodable? = nil, error: MCPError? = nil) {
        jsonrpc = JSON_RPC_VERSION
        self.id = id
        self.result = result
        self.error = error
    }
}

/// JSON-RPC Error
public struct MCPError: Codable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - Tools

public struct MCPTool: Codable {
    public let name: String
    public let description: String
    public let inputSchema: AnyCodable

    public init(name: String, description: String, inputSchema: AnyCodable) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - AnyCodable Utility

/// Lightweight utility to allow arbitrary dictionaries with Codable
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let anyCodable as AnyCodable:
            try anyCodable.encode(to: encoder)
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}
