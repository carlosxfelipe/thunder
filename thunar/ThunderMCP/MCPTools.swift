//
//  MCPTools.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 22/05/26.
//

import Foundation

@MainActor
public protocol ThunderMCPDelegate: AnyObject {
    func getActiveTabPath() -> String?
    func getSelectedFiles() -> [String]
    func moveFiles(sourcePaths: [String], targetDir: String) -> Bool
    func compressItems(paths: [String], format: String) -> Bool
    func openInThunder(path: String) -> Bool
    func createFile(name: String) -> Bool
    func createFolder(name: String) -> Bool
}

@MainActor
public class MCPTools: MCPServerDelegate {
    public weak var delegate: ThunderMCPDelegate?

    public init() {}

    public var availableTools: [MCPTool] {
        return [
            MCPTool(
                name: "get_active_tab_path",
                description: "Gets the absolute path of the directory opened in the active tab of Thunder.",
                inputSchema: AnyCodable(["type": "object", "properties": [:]])
            ),
            MCPTool(
                name: "get_selected_files",
                description: "Returns the list of absolute paths of the currently selected files in Thunder.",
                inputSchema: AnyCodable(["type": "object", "properties": [:]])
            ),
            MCPTool(
                name: "move_files",
                description: "Moves the selected files to a new destination directory.",
                inputSchema: AnyCodable([
                    "type": "object",
                    "properties": [
                        "sourcePaths": ["type": "array", "items": ["type": "string"]],
                        "targetDir": ["type": "string"],
                    ],
                    "required": ["sourcePaths", "targetDir"],
                ])
            ),
            MCPTool(
                name: "compress_items",
                description: "Compresses selected files.",
                inputSchema: AnyCodable([
                    "type": "object",
                    "properties": [
                        "paths": ["type": "array", "items": ["type": "string"]],
                        "format": ["type": "string", "enum": ["zip", "tar.gz"]],
                    ],
                    "required": ["paths", "format"],
                ])
            ),
            MCPTool(
                name: "open_in_thunder",
                description: "Opens a folder or selects a specific file in the Thunder graphical interface.",
                inputSchema: AnyCodable([
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"],
                    ],
                    "required": ["path"],
                ])
            ),
            MCPTool(
                name: "create_file",
                description: "Creates a new empty file in the currently active tab's directory.",
                inputSchema: AnyCodable([
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                    ],
                    "required": ["name"],
                ])
            ),
            MCPTool(
                name: "create_folder",
                description: "Creates a new directory in the currently active tab's directory.",
                inputSchema: AnyCodable([
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                    ],
                    "required": ["name"],
                ])
            ),
        ]
    }

    // MARK: - MCPServerDelegate

    public func mcpServer(_: MCPServer, didReceiveRequest method: String, params: [String: AnyCodable]?) -> Result<AnyCodable, MCPError> {
        // 1. Handshake Initialize Request
        if method == "initialize" {
            let initializeResult = AnyCodable([
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:],
                ],
                "serverInfo": [
                    "name": "ThunderMCP",
                    "version": "1.0.0",
                ],
            ])
            return .success(initializeResult)
        }

        // 2. Tools List Request
        if method == "tools/list" {
            let toolsList = availableTools.map { AnyCodable([
                "name": AnyCodable($0.name),
                "description": AnyCodable($0.description),
                "inputSchema": $0.inputSchema,
            ]) }
            let result = AnyCodable(["tools": AnyCodable(toolsList)])
            return .success(result)
        }

        // 3. Tools Call Request
        if method == "tools/call" {
            guard let name = params?["name"]?.value as? String else {
                return .failure(MCPError(code: -32602, message: "Invalid params: Tool name is missing"))
            }

            let args = params?["arguments"]?.value as? [String: Any] ?? [:]

            switch name {
            case "get_active_tab_path":
                if let path = delegate?.getActiveTabPath() {
                    return .success(AnyCodable([
                        "content": AnyCodable([
                            AnyCodable(["type": "text", "text": AnyCodable(path)]),
                        ]),
                    ]))
                } else {
                    return .success(AnyCodable([
                        "content": AnyCodable([
                            AnyCodable(["type": "text", "text": AnyCodable("Error: No active tab found. Please make sure Thunder is open and has an active tab.")]),
                        ]),
                        "isError": AnyCodable(true),
                    ]))
                }

            case "get_selected_files":
                let files = delegate?.getSelectedFiles() ?? []
                if files.isEmpty {
                    return .success(AnyCodable([
                        "content": AnyCodable([
                            AnyCodable(["type": "text", "text": AnyCodable("Error: No files are currently selected in Thunder.")]),
                        ]),
                        "isError": AnyCodable(true),
                    ]))
                }
                return .success(AnyCodable([
                    "content": AnyCodable([
                        AnyCodable(["type": "text", "text": AnyCodable(files.joined(separator: "\n"))]),
                    ]),
                ]))

            case "move_files":
                guard let sourcePaths = args["sourcePaths"] as? [String],
                      let targetDir = args["targetDir"] as? String
                else {
                    return .failure(MCPError(code: -32602, message: "Invalid params: Missing sourcePaths or targetDir"))
                }
                let success = delegate?.moveFiles(sourcePaths: sourcePaths, targetDir: targetDir) ?? false
                return .success(AnyCodable([
                    "content": AnyCodable([
                        AnyCodable(["type": "text", "text": AnyCodable(success ? "Moved successfully" : "Failed to move files. Please verify that the target directory exists.")]),
                    ]),
                    "isError": AnyCodable(!success),
                ]))

            case "compress_items":
                guard let paths = args["paths"] as? [String],
                      let format = args["format"] as? String
                else {
                    return .failure(MCPError(code: -32602, message: "Invalid params: Missing paths or format"))
                }
                let success = delegate?.compressItems(paths: paths, format: format) ?? false
                return .success(AnyCodable([
                    "content": AnyCodable([
                        AnyCodable(["type": "text", "text": AnyCodable(success ? "Compressed successfully" : "Failed to compress files.")]),
                    ]),
                    "isError": AnyCodable(!success),
                ]))

            case "open_in_thunder":
                guard let path = args["path"] as? String else {
                    return .failure(MCPError(code: -32602, message: "Invalid params: Missing path"))
                }
                let success = delegate?.openInThunder(path: path) ?? false
                return .success(AnyCodable([
                    "content": AnyCodable([
                        AnyCodable(["type": "text", "text": AnyCodable(success ? "Opened successfully" : "Failed to open path in Thunder.")]),
                    ]),
                    "isError": AnyCodable(!success),
                ]))

            case "create_file":
                guard let name = args["name"] as? String else {
                    return .failure(MCPError(code: -32602, message: "Invalid params: Missing name"))
                }
                let success = delegate?.createFile(name: name) ?? false
                return .success(AnyCodable([
                    "content": AnyCodable([
                        AnyCodable(["type": "text", "text": AnyCodable(success ? "File created successfully" : "Failed to create file. Please check if a file with the same name already exists.")]),
                    ]),
                    "isError": AnyCodable(!success),
                ]))

            case "create_folder":
                guard let name = args["name"] as? String else {
                    return .failure(MCPError(code: -32602, message: "Invalid params: Missing name"))
                }
                let success = delegate?.createFolder(name: name) ?? false
                return .success(AnyCodable([
                    "content": AnyCodable([
                        AnyCodable(["type": "text", "text": AnyCodable(success ? "Folder created successfully" : "Failed to create folder. Please check if a folder with the same name already exists.")]),
                    ]),
                    "isError": AnyCodable(!success),
                ]))

            default:
                return .failure(MCPError(code: -32601, message: "Tool not found: \(name)"))
            }
        }

        // 4. Unsupported JSON-RPC Method
        return .failure(MCPError(code: -32601, message: "Method not found: \(method)"))
    }
}
