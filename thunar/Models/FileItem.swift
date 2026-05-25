//
//  FileItem.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileSize: Int64
    let creationDate: Date
    let modificationDate: Date
    let tags: [FinderTag]
    let isHidden: Bool

    nonisolated init(url: URL) {
        id = UUID()
        self.url = url
        name = url.lastPathComponent
        isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey, .isHiddenKey])
        fileSize = Int64(resourceValues?.fileSize ?? 0)
        creationDate = resourceValues?.creationDate ?? Date()
        modificationDate = resourceValues?.contentModificationDate ?? Date()
        tags = (resourceValues?.tagNames ?? []).compactMap { name in
            FinderTag.allCases.first { $0.rawValue == name || $0.localizedPortugueseName == name }
        }

        let isHiddenValue = resourceValues?.isHidden ?? false
        isHidden = name.hasPrefix(".") || isHiddenValue
    }

    var icon: Image {
        let nsImage = NSWorkspace.shared.icon(forFile: url.path)
        return Image(nsImage: nsImage)
    }

    var formattedSize: String {
        if isDirectory {
            return "—"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: modificationDate)
    }

    var isImage: Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    var isSystemProtected: Bool {
        if url.path == "/" { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        if url.standardizedFileURL == home { return true }

        let parent = url.deletingLastPathComponent().standardizedFileURL
        if parent.path == "/" {
            let protectedFolders = [
                "system", "library", "users", "applications",
                "bin", "sbin", "usr", "var", "private", "etc", "tmp", "dev", "opt", "volumes", "cores",
            ]
            return protectedFolders.contains(url.lastPathComponent.lowercased())
        }
        if parent.path.lowercased() == "/users" {
            return true
        }
        return false
    }

    var isExecutable: Bool {
        guard !isDirectory else { return false }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attrs?[.posixPermissions] as? NSNumber
        return ((permissions?.uint16Value ?? 0) & 0o111) != 0
    }

    var isInTCCProtectedDirectory: Bool {
        let path = url.standardizedFileURL.path.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path.lowercased()
        let protectedPaths = [
            "\(home)/desktop",
            "\(home)/documents",
            "\(home)/downloads",
        ]
        return protectedPaths.contains { path.hasPrefix($0) }
    }

    var isScript: Bool {
        guard !isDirectory else { return false }
        if isInTCCProtectedDirectory { return false }
        let scriptExtensions = ["sh", "py", "command", "pl", "rb", "js", "bash", "zsh", "ts"]
        return scriptExtensions.contains(url.pathExtension.lowercased())
    }
}
