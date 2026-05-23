//
//  MCPServer.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 22/05/26.
//

import Foundation
import Network

public protocol MCPServerDelegate: AnyObject {
    func mcpServer(_ server: MCPServer, didReceiveRequest method: String, params: [String: AnyCodable]?) -> AnyCodable?
}

public class MCPServer {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var sseConnections: [NWConnection] = []
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
        listener?.cancel()
        for connection in sseConnections {
            connection.cancel()
        }
        sseConnections.removeAll()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty, let string = String(data: data, encoding: .utf8) {
                self.processReceivedData(string, connection: connection)
            }

            if isComplete || error != nil {
                self.sseConnections.removeAll { $0 === connection }
                connection.cancel()
            } else {
                self.receive(on: connection)
            }
        }
    }

    private func processReceivedData(_ string: String, connection: NWConnection) {
        if string.hasPrefix("GET ") || string.hasPrefix("POST ") {
            // Very simple HTTP interceptor for SSE / POST endpoints
            if string.contains("/sse") {
                setupSSE(connection: connection)
            } else if string.contains("/message") {
                // Extract body for POST
                if let bodyStart = string.range(of: "\r\n\r\n") {
                    let body = String(string[bodyStart.upperBound...])
                    if let data = body.data(using: .utf8) {
                        handleJSONRPC(data, connection: connection)
                    }
                }

                // Respond to POST
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
            }
        }
    }

    private func setupSSE(connection: NWConnection) {
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        \r\n
        """

        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.sseConnections.append(connection)
                self?.sendEndpointReadyEvent(to: connection)
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
            var responseResult: AnyCodable? = nil

            // Dispatch to delegate on main thread to interact with UI
            DispatchQueue.main.sync {
                responseResult = self.delegate?.mcpServer(self, didReceiveRequest: request.method, params: request.params)
            }

            let mcpResponse = MCPResponse(id: request.id, result: responseResult)
            sendSSEMessage(mcpResponse)

        } else if let request = try? decoder.decode(MCPNotification.self, from: data) {
            // Ignore notifications for now
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

        for connection in sseConnections {
            connection.send(content: payloadData, completion: .contentProcessed { _ in })
        }
    }
}
