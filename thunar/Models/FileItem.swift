//
//  FileItem.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import AppKit
import Foundation
import SwiftUI

struct FileItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileSize: Int64
    let creationDate: Date
    let modificationDate: Date
    let tags: [FinderTag]

    nonisolated init(url: URL) {
        id = UUID()
        self.url = url
        name = url.lastPathComponent
        isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey])
        fileSize = Int64(resourceValues?.fileSize ?? 0)
        creationDate = resourceValues?.creationDate ?? Date()
        modificationDate = resourceValues?.contentModificationDate ?? Date()
        tags = (resourceValues?.tagNames ?? []).compactMap { name in
            FinderTag.allCases.first { $0.rawValue == name }
        }
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
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: modificationDate)
    }
}
