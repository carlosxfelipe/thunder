//
//  ThunderMCPManager.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 22/05/26.
//

import AppKit
import Foundation

@MainActor
public class ThunderMCPManager: ThunderMCPDelegate {
    public static let shared = ThunderMCPManager()

    private var server: MCPServer
    private var tools: MCPTools
    weak var activeTabManager: TabManagerService?

    private init() {
        server = MCPServer(port: 8888)
        tools = MCPTools()

        server.delegate = tools
        tools.delegate = self
    }

    public func start() {
        do {
            try server.start()
        } catch {
            print("Failed to start MCP Server: \(error)")
        }
    }

    public func stop() {
        server.stop()
    }

    public func updateState(enabled: Bool, port: Int) {
        stop()
        if enabled {
            server = MCPServer(port: UInt16(port))
            server.delegate = tools
            start()
        }
    }

    // MARK: - ThunderMCPDelegate

    public func getActiveTabPath() -> String? {
        return activeTabManager?.activeFileManager?.currentDirectory.path
    }

    public func getSelectedFiles() -> [String] {
        if let selected = activeTabManager?.activeFileManager?.selectedURLs {
            return selected.map { $0.path }
        }
        return []
    }

    public func moveFiles(sourcePaths: [String], targetDir: String) -> Bool {
        guard let fm = activeTabManager?.activeFileManager else { return false }
        let urls = sourcePaths.map { URL(fileURLWithPath: $0) }
        let targetURL = URL(fileURLWithPath: targetDir)
        fm.moveItems(urls, to: targetURL)
        return true
    }

    public func compressItems(paths: [String], format: String) -> Bool {
        guard let fm = activeTabManager?.activeFileManager else { return false }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let compFormat: CompressionFormat = (format == "zip") ? .zip : .tarGz
        let items = urls.map { FileItem(url: $0) }

        // Uses the first file's name as the base for the archive
        let name = urls.first?.lastPathComponent ?? "Archive"
        fm.compressItems(items, to: name, format: compFormat)
        return true
    }

    public func openInThunder(path: String) -> Bool {
        guard let fm = activeTabManager?.activeFileManager else { return false }
        fm.navigateTo(URL(fileURLWithPath: path))
        return true
    }

    public func createFile(name: String) -> Bool {
        guard let fm = activeTabManager?.activeFileManager else { return false }
        fm.createFile(name: name)
        return true
    }

    public func createFolder(name: String) -> Bool {
        guard let fm = activeTabManager?.activeFileManager else { return false }
        fm.createFolder(name: name)
        return true
    }
}
