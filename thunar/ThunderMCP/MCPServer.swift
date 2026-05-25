//
//  MCPServer.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 22/05/26.
//

import Foundation
import Network

public protocol MCPServerDelegate: AnyObject {
    func mcpServer(_ server: MCPServer, didReceiveRequest method: String, params: [String: AnyCodable]?) -> Result<AnyCodable, MCPError>
}

public class MCPServer {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var sseConnections: [NWConnection] = []
    private var connectionBuffers: [ObjectIdentifier: Data] = [:]
    private let queue = DispatchQueue(label: "com.thunder.mcp.server")

    public weak var delegate: MCPServerDelegate?

    public init(port: UInt16 = 8888) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        listener = try NWListener(using: parameters, on: port)

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("MCP Server listening on port \(self?.port.rawValue ?? 0)")
            case let .failed(error):
                print("MCP Server failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.listener?.cancel()
            for connection in self.sseConnections {
                connection.cancel()
            }
            self.sseConnections.removeAll()
            self.connectionBuffers.removeAll()
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        // Strictly filter connections to only allow localhost
        let remoteEndpoint = connection.endpoint
        if case let .hostPort(host, _) = remoteEndpoint {
            let hostStr = "\(host)"
            if hostStr != "127.0.0.1" && hostStr != "::1" && hostStr != "localhost" {
                print("Rejected connection from unauthorized host: \(hostStr)")
                connection.cancel()
                return
            }
        } else {
            connection.cancel()
            return
        }

        let id = ObjectIdentifier(connection)
        queue.async { [weak self] in
            guard let self = self else { return }
            self.connectionBuffers[id] = Data()
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.queue.async {
                    self.connectionBuffers[id, default: Data()].append(data)
                    self.processBuffer(for: connection)
                }
            }

            if isComplete || error != nil {
                self.queue.async {
                    self.connectionBuffers.removeValue(forKey: id)
                }
                self.queue.async { [weak self] in
                    self?.sseConnections.removeAll { $0 === connection }
                }
                connection.cancel()
            } else {
                self.receive(on: connection)
            }
        }
    }

    private func processBuffer(for connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard var buffer = connectionBuffers[id], !buffer.isEmpty else { return }

        while !buffer.isEmpty {
            // Find the header-body separator \r\n\r\n
            guard let rangeOfSeparator = buffer.range(of: Data([13, 10, 13, 10])) else {
                break // Wait for more data to get full headers
            }

            let headerData = buffer.subdata(in: 0 ..< rangeOfSeparator.lowerBound)
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                // Invalid headers, close connection
                connectionBuffers[id] = nil
                connection.cancel()
                return
            }

            // Parse Content-Length from headers
            var contentLength = 0
            let lines = headerString.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else {
                connectionBuffers[id] = nil
                connection.cancel()
                return
            }

            for line in lines.dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0].lowercased() == "content-length", let len = Int(parts[1]) {
                    contentLength = len
                }
            }

            let bodyStart = rangeOfSeparator.upperBound
            let totalRequestLength = bodyStart + contentLength

            // Check if we have received the complete body
            if buffer.count < totalRequestLength {
                break // Wait for more data to get the complete body
            }

            // Extract body data
            let bodyData = buffer.subdata(in: bodyStart ..< totalRequestLength)

            // Consume request from buffer
            buffer.removeSubrange(0 ..< totalRequestLength)
            connectionBuffers[id] = buffer

            // Route request
            if requestLine.contains("/sse") {
                setupSSE(connection: connection)
            } else if requestLine.contains("/message") {
                handleJSONRPC(bodyData, connection: connection)

                // Respond to POST
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
            } else {
                // Respond to unknown route with 404
                let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func setupSSE(connection: NWConnection) {
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        \r\n
        """

        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.queue.async {
                    self?.sseConnections.append(connection)
                    self?.sendEndpointReadyEvent(to: connection)
                }
            }
        })
    }

    private func sendEndpointReadyEvent(to connection: NWConnection) {
        let event = "event: endpoint\ndata: /message\n\n"
        connection.send(content: event.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    private func handleJSONRPC(_ data: Data, connection _: NWConnection) {
        let decoder = JSONDecoder()
        if let request = try? decoder.decode(MCPRequest.self, from: data) {
            var responseResult: Result<AnyCodable, MCPError>? = nil

            // Dispatch to delegate on main thread to interact with UI safely
            DispatchQueue.main.sync {
                responseResult = self.delegate?.mcpServer(self, didReceiveRequest: request.method, params: request.params)
            }

            let mcpResponse: MCPResponse
            if let responseResult = responseResult {
                switch responseResult {
                case let .success(result):
                    mcpResponse = MCPResponse(id: request.id, result: result)
                case let .failure(error):
                    mcpResponse = MCPResponse(id: request.id, error: error)
                }
            } else {
                let error = MCPError(code: -32601, message: "Method not found: \(request.method)")
                mcpResponse = MCPResponse(id: request.id, error: error)
            }
            sendSSEMessage(mcpResponse)

        } else if let request = try? decoder.decode(MCPNotification.self, from: data) {
            // Log initialized notifications
            if request.method == "notifications/initialized" {
                print("MCP Client Initialized")
            }
        } else {
            print("Failed to decode JSON-RPC data")
        }
    }

    private func sendSSEMessage<T: Codable>(_ message: T) {
        guard let data = try? JSONEncoder().encode(message),
              let stringData = String(data: data, encoding: .utf8) else { return }

        let ssePayload = "event: message\ndata: \(stringData)\n\n"
        let payloadData = ssePayload.data(using: .utf8)

        queue.async { [weak self] in
            guard let self = self else { return }
            for connection in self.sseConnections {
                connection.send(content: payloadData, completion: .contentProcessed { _ in })
            }
        }
    }

}
