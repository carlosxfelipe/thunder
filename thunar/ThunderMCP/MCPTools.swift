//
//  MCPTools.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 22/05/26.
//

import Foundation

public protocol ThunderMCPDelegate: AnyObject {
    func getActiveTabPath() -> String?
    func getSelectedFiles() -> [String]
    func moveFiles(sourcePaths: [String], targetDir: String) -> Bool
    func compressItems(paths: [String], format: String) -> Bool
    func openInThunder(path: String) -> Bool
}

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
        ]
    }

    // MARK: - MCPServerDelegate

    public func mcpServer(_: MCPServer, didReceiveRequest method: String, params: [String: AnyCodable]?) -> AnyCodable? {
        if method == "tools/list" {
            let toolsList = availableTools.map { AnyCodable([
                "name": AnyCodable($0.name),
                "description": AnyCodable($0.description),
                "inputSchema": $0.inputSchema,
            ]) }
            return AnyCodable(["tools": AnyCodable(toolsList)])
        }

        if method == "tools/call" {
            guard let name = params?["name"]?.value as? String else {
                return AnyCodable(["error": "Tool name is missing"])
            }

            let args = params?["arguments"]?.value as? [String: Any] ?? [:]

            switch name {
            case "get_active_tab_path":
                let path = delegate?.getActiveTabPath() ?? ""
                return AnyCodable([
                    "content": AnyCodable([
                        AnyCodable(["type": "text", "text": AnyCodable(path)]),
                    ]),
                ])

            case "get_selected_files":
                let files = delegate?.getSelectedFiles() ?? []
                return AnyCodable([
                    "content": AnyCodable([
                        AnyCodable(["type": "text", "text": AnyCodable(files.joined(separator: "\n"))]),
                    ]),
                ])

            case "move_files":
                if let sourcePaths = args["sourcePaths"] as? [String],
                   let targetDir = args["targetDir"] as? String
                {
                    let success = delegate?.moveFiles(sourcePaths: sourcePaths, targetDir: targetDir) ?? false
                    return AnyCodable([
                        "content": AnyCodable([
                            AnyCodable(["type": "text", "text": AnyCodable(success ? "Moved successfully" : "Failed to move files")]),
                        ]),
                    ])
                }

            case "compress_items":
                if let paths = args["paths"] as? [String],
                   let format = args["format"] as? String
                {
                    let success = delegate?.compressItems(paths: paths, format: format) ?? false
                    return AnyCodable([
                        "content": AnyCodable([
                            AnyCodable(["type": "text", "text": AnyCodable(success ? "Compressed successfully" : "Failed to compress files")]),
                        ]),
                    ])
                }

            case "open_in_thunder":
                if let path = args["path"] as? String {
                    let success = delegate?.openInThunder(path: path) ?? false
                    return AnyCodable([
                        "content": AnyCodable([
                            AnyCodable(["type": "text", "text": AnyCodable(success ? "Opened successfully" : "Failed to open path")]),
                        ]),
                    ])
                }

            default:
                return AnyCodable(["error": "Tool not found"])
            }
        }

        return nil
    }
}
