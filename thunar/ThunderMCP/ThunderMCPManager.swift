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

    public func listDirectoryContents(path: String?) -> [[String: Any]]? {
        let dirPath = path ?? getActiveTabPath()
        guard let dirPath = dirPath else { return nil }
        let url = URL(fileURLWithPath: dirPath)

        var options: FileManager.DirectoryEnumerationOptions = []
        if let activeFM = activeTabManager?.activeFileManager, !activeFM.showHiddenFiles {
            options.insert(.skipsHiddenFiles)
        } else {
            options.insert(.skipsHiddenFiles)
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey, .isHiddenKey],
                options: options
            )

            let formatter = ISO8601DateFormatter()
            return contents.map { itemUrl in
                let item = FileItem(url: itemUrl)
                return [
                    "name": item.name,
                    "path": item.url.path,
                    "isDirectory": item.isDirectory,
                    "fileSize": item.fileSize,
                    "formattedSize": item.formattedSize,
                    "creationDate": formatter.string(from: item.creationDate),
                    "modificationDate": formatter.string(from: item.modificationDate),
                    "isHidden": item.isHidden,
                    "tags": item.tags.map { $0.rawValue },
                ]
            }
        } catch {
            return nil
        }
    }

    public func getFileMetadata(path: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let item = FileItem(url: url)
        let formatter = ISO8601DateFormatter()
        return [
            "name": item.name,
            "path": item.url.path,
            "isDirectory": item.isDirectory,
            "fileSize": item.fileSize,
            "formattedSize": item.formattedSize,
            "creationDate": formatter.string(from: item.creationDate),
            "modificationDate": formatter.string(from: item.modificationDate),
            "isHidden": item.isHidden,
            "isImage": item.isImage,
            "isSystemProtected": item.isSystemProtected,
            "tags": item.tags.map { $0.rawValue },
        ]
    }

    public func renameItem(path: String, newName: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let item = FileItem(url: url)
        guard !item.isSystemProtected else { return false }

        let parentDir = url.deletingLastPathComponent()
        let newURL = parentDir.appendingPathComponent(newName)

        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            if let activeFM = activeTabManager?.activeFileManager {
                if activeFM.currentDirectory.standardizedFileURL.path == parentDir.standardizedFileURL.path {
                    activeFM.loadDirectory()
                }
            }
            return true
        } catch {
            print("MCP Rename Error: \(error)")
            return false
        }
    }

    public func decompressItem(path: String) -> Bool {
        guard let activeFM = activeTabManager?.activeFileManager else { return false }
        let url = URL(fileURLWithPath: path)
        let item = FileItem(url: url)

        guard activeFM.isSupportedArchive(item) else { return false }
        activeFM.extractArchiveItem(item)
        return true
    }

    public func rotateImage(path: String, degrees: Double, saveAsCopy: Bool) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let ciImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }

        var orientation: CGImagePropertyOrientation
        switch Int(degrees) {
        case 90:
            orientation = .right
        case 180:
            orientation = .down
        case 270:
            orientation = .left
        default:
            orientation = .up
        }

        let rotated = ciImage.oriented(orientation)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(rotated, from: rotated.extent) else { return nil }

        let newBitmap = NSBitmapImageRep(cgImage: cgImage)
        let ext = url.pathExtension.lowercased()
        let type: NSBitmapImageRep.FileType = (ext == "png") ? .png : .jpeg

        var targetURL = url
        if saveAsCopy {
            let dir = url.deletingLastPathComponent()
            let base = url.deletingPathExtension().lastPathComponent
            let extensionStr = url.pathExtension

            var newURL = dir.appendingPathComponent("\(base)_edited.\(extensionStr)")
            var counter = 2
            while FileManager.default.fileExists(atPath: newURL.path) {
                newURL = dir.appendingPathComponent("\(base)_edited_\(counter).\(extensionStr)")
                counter += 1
            }
            targetURL = newURL
        }

        if let data = newBitmap.representation(using: type, properties: [:]) {
            do {
                try data.write(to: targetURL)
                if let activeFM = activeTabManager?.activeFileManager {
                    if activeFM.currentDirectory.standardizedFileURL.path == targetURL.deletingLastPathComponent().standardizedFileURL.path {
                        activeFM.loadDirectory()
                    }
                }
                return targetURL.path
            } catch {
                return nil
            }
        }
        return nil
    }

    public func resizeImage(path: String, width: Double, height: Double, unit: String, maintainAspectRatio: Bool, saveAsCopy: Bool) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let image = NSImage(contentsOf: url) else { return nil }
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        var targetWidth = width
        var targetHeight = height

        if unit == "percent" {
            targetWidth = (width / 100.0) * originalSize.width
            targetHeight = (height / 100.0) * originalSize.height
        }

        if maintainAspectRatio {
            let aspect = originalSize.height / originalSize.width
            targetHeight = targetWidth * aspect
        }

        guard targetWidth > 0, targetHeight > 0 else { return nil }

        guard let ciImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        let contextCI = CIContext(options: nil)
        guard let cgImage = contextCI.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = cgImage.bitmapInfo.rawValue

        guard let context = CGContext(data: nil,
                                      width: Int(targetWidth),
                                      height: Int(targetHeight),
                                      bitsPerComponent: cgImage.bitsPerComponent,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let newCGImage = context.makeImage() else { return nil }
        let newBitmap = NSBitmapImageRep(cgImage: newCGImage)
        let ext = url.pathExtension.lowercased()
        let type: NSBitmapImageRep.FileType = (ext == "png") ? .png : .jpeg

        var targetURL = url
        if saveAsCopy {
            let dir = url.deletingLastPathComponent()
            let base = url.deletingPathExtension().lastPathComponent
            let extensionStr = url.pathExtension

            var newURL = dir.appendingPathComponent("\(base)_edited.\(extensionStr)")
            var counter = 2
            while FileManager.default.fileExists(atPath: newURL.path) {
                newURL = dir.appendingPathComponent("\(base)_edited_\(counter).\(extensionStr)")
                counter += 1
            }
            targetURL = newURL
        }

        if let data = newBitmap.representation(using: type, properties: [:]) {
            do {
                try data.write(to: targetURL)
                if let activeFM = activeTabManager?.activeFileManager {
                    if activeFM.currentDirectory.standardizedFileURL.path == targetURL.deletingLastPathComponent().standardizedFileURL.path {
                        activeFM.loadDirectory()
                    }
                }
                return targetURL.path
            } catch {
                return nil
            }
        }
        return nil
    }

    public func trashItems(paths: [String]) -> Bool {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let items = urls.map { FileItem(url: $0) }
        let nonProtectedItems = items.filter { !$0.isSystemProtected }
        guard !nonProtectedItems.isEmpty else { return false }

        var success = true
        var trashedCount = 0
        for item in nonProtectedItems {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                trashedCount += 1
            } catch {
                print("MCP Trash Error for \(item.name): \(error)")
                success = false
            }
        }

        if trashedCount > 0 {
            if let activeFM = activeTabManager?.activeFileManager {
                activeFM.loadDirectory()
                if trashedCount == 1, let firstItem = nonProtectedItems.first {
                    activeFM.postStatus(String(format: LanguageManager.shared.local("moved_to_trash_singular"), firstItem.name))
                } else {
                    activeFM.postStatus(String(format: LanguageManager.shared.local("moved_to_trash_plural"), trashedCount))
                }
            }
        }
        return success
    }
}
