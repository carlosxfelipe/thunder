//
//  FileManagerService.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import AppKit
import Combine
import Foundation
import SwiftUI

enum CompressionFormat: String, CaseIterable, Identifiable, Sendable {
    case zip = "ZIP (.zip)"
    case tarGz = "TAR GZ (.tar.gz)"
    case tarBz2 = "TAR BZ2 (.tar.bz2)"

    var id: String { rawValue }
    var extensionString: String {
        switch self {
        case .zip: return "zip"
        case .tarGz: return "tar.gz"
        case .tarBz2: return "tar.bz2"
        }
    }
}

@MainActor
class FileManagerService: ObservableObject {
    @Published var currentDirectory: URL
    @Published var files: [FileItem] = []
    @Published var selectedFiles: Set<FileItem> = []
    @Published var selectedURLs: [URL] = []
    @Published var navigationHistory: [URL] = []
    @Published var historyIndex: Int = 0
    @Published var favorites: [URL] = []
    private let favoritesKey = "sidebarFavorites"
    private let clipboardService = ClipboardService.shared
    private let languageManager = LanguageManager.shared

    var clipboard: (urls: [URL], action: ClipboardService.ClipboardAction)? {
        clipboardService.clipboard
    }

    @Published var errorMessage: String? = nil
    @Published var statusMessage: String? = nil
    @Published var isProcessing: Bool = false
    @Published var showHiddenFiles: Bool = false {
        didSet {
            loadDirectory()
        }
    }

    @Published var searchTag: FinderTag? = nil {
        didSet {
            if let tag = searchTag {
                startTagSearch(tag)
            } else {
                stopTagSearch()
                loadDirectory()
            }
        }
    }

    private var metadataQuery = NSMetadataQuery()
    private var queryObservers: [AnyCancellable] = []
    private var fileSearchTask: Task<Void, Never>?

    private let fileManager = FileManager.default
    private var volumeUnmountObserver: NSObjectProtocol?
    private var fileSystemChangeObserver: NSObjectProtocol?
    private static let fileSystemDidChangeNotification = Notification.Name("FileManagerServiceFileSystemDidChange")

    init() {
        let home = fileManager.homeDirectoryForCurrentUser
        currentDirectory = home
        navigationHistory.append(home)
        historyIndex = 0
        loadDirectory()
        loadFavorites()
        registerVolumeObservers()
    }

    deinit {
        if let observer = volumeUnmountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = fileSystemChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func registerVolumeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        volumeUnmountObserver = center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract URL before entering Task; URL is Sendable, Notification is not.
            let unmountedURL = (notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)
                ?? (notification.userInfo?["NSDevicePath"] as? String).map { URL(fileURLWithPath: $0) }
            guard let unmountedURL else { return }
            Task { @MainActor [weak self] in
                self?.navigateAwayIfInside(unmountedURL)
            }
        }

        fileSystemChangeObserver = NotificationCenter.default.addObserver(
            forName: Self.fileSystemDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let urls = notification.userInfo?["urls"] as? [URL] ?? []
            Task { @MainActor [weak self] in
                self?.reloadIfViewingAny(urls)
            }
        }
    }

    private func reloadIfViewingAny(_ urls: [URL]) {
        let currentPath = currentDirectory.standardizedFileURL.path
        let shouldReload = urls.contains { url in
            url.standardizedFileURL.path == currentPath
        }

        if shouldReload {
            loadDirectory()
        }
    }

    private func postFileSystemChange(for urls: [URL]) {
        NotificationCenter.default.post(
            name: Self.fileSystemDidChangeNotification,
            object: self,
            userInfo: ["urls": urls]
        )
    }

    private func navigateAwayIfInside(_ unmountedURL: URL) {
        let unmountedPath = unmountedURL.standardizedFileURL.path
        let currentPath = currentDirectory.standardizedFileURL.path
        if currentPath == unmountedPath || currentPath.hasPrefix(unmountedPath + "/") {
            postStatus(String(format: languageManager.local("volume_unmounted"), unmountedURL.lastPathComponent))
            navigateTo(fileManager.homeDirectoryForCurrentUser)
        }
    }

    func postStatus(_ message: String, autoClear: Bool = true) {
        statusMessage = message
        if autoClear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if self.statusMessage == message {
                    self.statusMessage = nil
                }
            }
        }
    }

    func loadDirectory(_ url: URL? = nil) {
        fileSearchTask?.cancel()
        fileSearchTask = nil
        if statusMessage?.hasPrefix(languageManager.local("searching")) == true {
            isProcessing = false
            statusMessage = nil
        }
        let targetURL = url ?? currentDirectory

        Task {
            do {
                var options: FileManager.DirectoryEnumerationOptions = []
                if !self.showHiddenFiles {
                    options.insert(.skipsHiddenFiles)
                }

                let contents = try fileManager.contentsOfDirectory(
                    at: targetURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey, .isHiddenKey],
                    options: options
                )

                // Heavy processing (mapping and sorting) in a separate thread to avoid blocking the UI.
                let fileItems = await Task.detached {
                    contents.map { FileItem(url: $0) }
                        .sorted { $0.name.lowercased() < $1.name.lowercased() }
                }.value

                self.files = fileItems
                self.currentDirectory = targetURL
                self.selectedFiles = []
                self.errorMessage = nil
            } catch {
                if targetURL.lastPathComponent == ".Trash" || error.localizedDescription.contains("permission") {
                    self.errorMessage = "\(languageManager.local("access_denied_title"))\n\n\(languageManager.local("access_denied_message"))"
                } else {
                    self.errorMessage = String(format: languageManager.local("access_error_generic"), error.localizedDescription)
                }
            }
        }
    }

    func searchFiles(matching query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        fileSearchTask?.cancel()

        guard !trimmedQuery.isEmpty else {
            fileSearchTask = nil
            if statusMessage?.hasPrefix(languageManager.local("searching")) == true {
                isProcessing = false
                statusMessage = nil
            }
            loadDirectory()
            return
        }

        let rootURL = currentDirectory
        let shouldShowHiddenFiles = showHiddenFiles
        isProcessing = true
        statusMessage = String(format: languageManager.local("searching_query"), trimmedQuery)

        fileSearchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let results = await Task.detached {
                var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
                if !shouldShowHiddenFiles {
                    options.insert(.skipsHiddenFiles)
                }

                guard let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey, .isHiddenKey],
                    options: options
                ) else {
                    return [FileItem]()
                }

                var items: [FileItem] = []
                while let url = enumerator.nextObject() as? URL {
                    if Task.isCancelled {
                        return [FileItem]()
                    }
                    if url.lastPathComponent.localizedStandardContains(trimmedQuery) {
                        items.append(FileItem(url: url))
                    }
                }

                return items.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }.value

            guard !Task.isCancelled else { return }

            self.files = results
            self.selectedFiles = []
            self.isProcessing = false
            if results.isEmpty {
                self.postStatus(String(format: languageManager.local("no_items_found_for"), trimmedQuery))
            } else {
                self.statusMessage = nil
            }
        }
    }

    func navigateTo(_ url: URL) {
        if searchTag != nil {
            searchTag = nil
        }

        // Add to history if we're not just going back/forward
        if historyIndex == navigationHistory.count - 1 {
            if navigationHistory.last != url {
                navigationHistory.append(url)
                historyIndex = navigationHistory.count - 1
            }
        } else {
            // If we're in the middle of history, truncate and add new
            navigationHistory = Array(navigationHistory.prefix(through: historyIndex))
            if navigationHistory.last != url {
                navigationHistory.append(url)
            }
            historyIndex = navigationHistory.count - 1
        }

        loadDirectory(url)
    }

    func navigateBack() {
        guard historyIndex > 0 else { return }
        if searchTag != nil {
            searchTag = nil
        }
        historyIndex -= 1
        let url = navigationHistory[historyIndex]
        loadDirectory(url)
    }

    func navigateForward() {
        guard historyIndex < navigationHistory.count - 1 else { return }
        if searchTag != nil {
            searchTag = nil
        }
        historyIndex += 1
        let url = navigationHistory[historyIndex]
        loadDirectory(url)
    }

    func navigateToParent() {
        if searchTag != nil {
            searchTag = nil
        }
        let parent = currentDirectory.deletingLastPathComponent()
        navigateTo(parent)
    }

    func goToHome() {
        navigateTo(fileManager.homeDirectoryForCurrentUser)
    }

    func goToDesktop() {
        let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        navigateTo(desktopURL)
    }

    func goToDocuments() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        navigateTo(documentsURL)
    }

    func goToDownloads() {
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        navigateTo(downloadsURL)
    }

    func createFolder(name: String) {
        let newFolderURL = currentDirectory.appendingPathComponent(name)

        if fileManager.fileExists(atPath: newFolderURL.path) {
            errorMessage = String(format: languageManager.local("item_exists"), name)
            return
        }

        do {
            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
            loadDirectory()
        } catch {
            errorMessage = String(format: languageManager.local("create_folder_error"), error.localizedDescription)
        }
    }

    func createFile(name: String) {
        let newFileURL = currentDirectory.appendingPathComponent(name)

        if fileManager.fileExists(atPath: newFileURL.path) {
            errorMessage = String(format: languageManager.local("item_exists"), name)
            return
        }

        if fileManager.createFile(atPath: newFileURL.path, contents: nil) {
            loadDirectory()
        } else {
            errorMessage = languageManager.local("create_file_error")
        }
    }

    func deleteItem(_ item: FileItem) {
        do {
            try fileManager.trashItem(at: item.url, resultingItemURL: nil)
            loadDirectory()
            postStatus(String(format: languageManager.local("moved_to_trash_singular"), item.name))
        } catch {
            errorMessage = String(format: languageManager.local("error_deleting_item"), error.localizedDescription)
        }
    }

    func deleteItems(_ items: [FileItem]) {
        let nonProtectedItems = items.filter { !$0.isSystemProtected }
        guard !nonProtectedItems.isEmpty else { return }

        var deletedCount = 0
        for item in nonProtectedItems {
            do {
                try fileManager.trashItem(at: item.url, resultingItemURL: nil)
                deletedCount += 1
            } catch {
                errorMessage = "Erro ao excluir \"\(item.name)\": \(error.localizedDescription)"
            }
        }

        loadDirectory()
        if deletedCount == 1, let item = nonProtectedItems.first {
            postStatus(String(format: languageManager.local("moved_to_trash_singular"), item.name))
        } else if deletedCount > 1 {
            postStatus(String(format: languageManager.local("moved_to_trash_plural"), deletedCount))
        }
    }

    func permanentDeleteItem(_ item: FileItem) {
        guard !item.isSystemProtected else { return }
        do {
            try fileManager.removeItem(at: item.url)
            loadDirectory()
            postStatus(String(format: languageManager.local("deleted_perm_singular"), item.name))
        } catch {
            errorMessage = String(format: languageManager.local("error_deleting_item"), error.localizedDescription)
        }
    }

    func permanentDeleteItems(_ items: [FileItem]) {
        let nonProtectedItems = items.filter { !$0.isSystemProtected }
        guard !nonProtectedItems.isEmpty else { return }

        var deletedCount = 0
        for item in nonProtectedItems {
            do {
                try fileManager.removeItem(at: item.url)
                deletedCount += 1
            } catch {
                errorMessage = "Erro ao excluir \"\(item.name)\": \(error.localizedDescription)"
            }
        }

        loadDirectory()
        if deletedCount == 1, let item = nonProtectedItems.first {
            postStatus(String(format: languageManager.local("deleted_perm_singular"), item.name))
        } else if deletedCount > 1 {
            postStatus(String(format: languageManager.local("deleted_perm_plural"), deletedCount))
        }
    }

    func openItem(_ item: FileItem) {
        if item.isDirectory {
            navigateTo(item.url)
        } else if isSupportedArchive(item) {
            extractArchiveItem(item)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openItems(_ items: [FileItem]) {
        for item in items {
            openItem(item)
        }
    }

    func compressItems(_ items: [FileItem], to name: String, format: CompressionFormat) {
        let currentDir = currentDirectory
        isProcessing = true
        postStatus(String(format: languageManager.local("compressing"), name), autoClear: false)

        let formatExt = format.extensionString
        let formatValue = format

        Task.detached {
            var finalName = name
            if !finalName.lowercased().hasSuffix(".\(formatExt)") {
                finalName += ".\(formatExt)"
            }
            var targetURL = currentDir.appendingPathComponent(finalName)

            if FileManager.default.fileExists(atPath: targetURL.path) {
                let currentFinalName = finalName
                let currentTargetURL = targetURL
                let response = await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = self.languageManager.local("item_exists_title")
                    alert.informativeText = String(format: self.languageManager.local("item_exists_message"), currentFinalName)
                    alert.icon = NSWorkspace.shared.icon(forFile: currentTargetURL.path)
                    alert.addButton(withTitle: self.languageManager.local("replace"))
                    alert.addButton(withTitle: self.languageManager.local("keep_both"))
                    alert.addButton(withTitle: self.languageManager.local("skip"))
                    return alert.runModal()
                }

                if response == .alertFirstButtonReturn {
                    do {
                        try FileManager.default.removeItem(at: targetURL)
                    } catch {
                        await MainActor.run {
                            self.isProcessing = false
                            self.errorMessage = "Erro ao substituir: \(error.localizedDescription)"
                            self.statusMessage = nil
                        }
                        return
                    }
                } else if response == .alertSecondButtonReturn {
                    var counter = 2
                    let base = finalName.replacingOccurrences(of: ".\(formatExt)", with: "")
                    while FileManager.default.fileExists(atPath: targetURL.path) {
                        finalName = "\(base) \(counter).\(formatExt)"
                        targetURL = currentDir.appendingPathComponent(finalName)
                        counter += 1
                    }
                } else {
                    await MainActor.run {
                        self.isProcessing = false
                        self.statusMessage = nil
                    }
                    return
                }
            }

            let finalTargetURL = targetURL
            let process = Process()
            process.currentDirectoryURL = currentDir

            if formatValue == .zip {
                if items.count == 1 {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", items.first!.url.path, finalTargetURL.path]
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    var args = ["-q", "-r", finalTargetURL.path]
                    for item in items {
                        args.append(item.url.lastPathComponent)
                    }
                    process.arguments = args
                }
            } else if formatValue == .tarGz {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                var args = ["-czf", finalTargetURL.path]
                for item in items {
                    args.append(item.url.lastPathComponent)
                }
                process.arguments = args
            } else if formatValue == .tarBz2 {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                var args = ["-cjf", finalTargetURL.path]
                for item in items {
                    args.append(item.url.lastPathComponent)
                }
                process.arguments = args
            }

            do {
                try process.run()
                process.waitUntilExit()

                await MainActor.run {
                    self.isProcessing = false
                    self.loadDirectory()
                }

                // Wait a brief moment for APFS filesystem catalog to sync, then refresh again to be absolutely sure
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    self.loadDirectory()
                    self.postStatus(String(format: self.languageManager.local("compress_success"), finalTargetURL.lastPathComponent))
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Erro ao comprimir: \(error.localizedDescription)"
                    self.statusMessage = nil
                }
            }
        }
    }

    func isSupportedArchive(_ item: FileItem) -> Bool {
        let ext = item.url.pathExtension.lowercased()
        if ext == "zip" || ext == "tar" || ext == "tgz" || ext == "tbz2" {
            return true
        }
        let path = item.url.path.lowercased()
        if path.hasSuffix(".tar.gz") || path.hasSuffix(".tar.bz2") {
            return true
        }
        return false
    }

    func extractArchiveItem(_ item: FileItem) {
        let currentDir = currentDirectory
        isProcessing = true
        postStatus(String(format: languageManager.local("extracting"), item.name), autoClear: false)

        Task.detached {
            var baseName = item.url.lastPathComponent
            let lowercasedName = baseName.lowercased()
            if lowercasedName.hasSuffix(".tar.gz") {
                baseName = String(baseName.dropLast(7))
            } else if lowercasedName.hasSuffix(".tar.bz2") {
                baseName = String(baseName.dropLast(8))
            } else {
                baseName = item.url.deletingPathExtension().lastPathComponent
            }

            var destinationURL = currentDir.appendingPathComponent(baseName, isDirectory: true)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let response = await MainActor.run { [baseName = baseName, destinationURL = destinationURL] in
                    let alert = NSAlert()
                    alert.messageText = self.languageManager.local("item_exists_title")
                    alert.informativeText = String(format: self.languageManager.local("item_exists_message"), baseName)
                    alert.icon = NSWorkspace.shared.icon(forFile: destinationURL.path)
                    alert.addButton(withTitle: self.languageManager.local("replace"))
                    alert.addButton(withTitle: self.languageManager.local("keep_both"))
                    alert.addButton(withTitle: self.languageManager.local("skip"))
                    return alert.runModal()
                }

                if response == .alertFirstButtonReturn {
                    do {
                        try FileManager.default.removeItem(at: destinationURL)
                    } catch {
                        await MainActor.run {
                            self.isProcessing = false
                            self.errorMessage = "Erro ao substituir: \(error.localizedDescription)"
                            self.statusMessage = nil
                        }
                        return
                    }
                } else if response == .alertSecondButtonReturn {
                    var counter = 2
                    while FileManager.default.fileExists(atPath: destinationURL.path) {
                        destinationURL = currentDir.appendingPathComponent("\(baseName) \(counter)", isDirectory: true)
                        counter += 1
                    }
                } else {
                    await MainActor.run {
                        self.isProcessing = false
                        self.statusMessage = nil
                    }
                    return
                }
            }

            do {
                try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: false)

                let process = Process()
                if item.url.pathExtension.lowercased() == "zip" {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    process.arguments = ["-x", "-k", item.url.path, destinationURL.path]
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    process.arguments = ["-xf", item.url.path, "-C", destinationURL.path]
                }

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    await MainActor.run {
                        self.isProcessing = false
                        self.loadDirectory()
                    }

                    // Wait a brief moment for APFS filesystem catalog to sync, then refresh again to be absolutely sure
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await MainActor.run {
                        self.loadDirectory()
                        self.postStatus(String(format: self.languageManager.local("extract_success"), item.name))
                    }
                } else {
                    try? FileManager.default.removeItem(at: destinationURL)
                    await MainActor.run {
                        self.isProcessing = false
                        self.errorMessage = "Erro ao descompactar \"\(item.name)\"."
                        self.statusMessage = nil
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: destinationURL)
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Erro ao descompactar: \(error.localizedDescription)"
                    self.statusMessage = nil
                }
            }
        }
    }

    func deleteSelectedItems() {
        for item in selectedFiles {
            deleteItem(item)
        }
    }

    func renameItem(_ item: FileItem, to newName: String) {
        guard !item.isSystemProtected else { return }
        let newURL = currentDirectory.appendingPathComponent(newName)

        do {
            try fileManager.moveItem(at: item.url, to: newURL)
            loadDirectory()
            postStatus(String(format: languageManager.local("renamed_to"), item.name, newName))
        } catch {
            print("Error renaming item: \(error)")
        }
    }

    /// Moves files/folders to a destination directory (used by drag & drop).
    func moveItems(_ urls: [URL], to destinationDir: URL) {
        let nonProtectedURLs = urls.filter { !isSystemProtected(url: $0) }
        guard !nonProtectedURLs.isEmpty else { return }

        var urlsToMove = nonProtectedURLs
        if nonProtectedURLs.count == 1, let firstURL = nonProtectedURLs.first,
           selectedURLs.contains(firstURL),
           selectedURLs.count > 1
        {
            urlsToMove = selectedURLs.filter { !isSystemProtected(url: $0) }
        }

        var movedCount = 0
        var affectedDirectories: Set<URL> = [destinationDir]
        var lastName = ""

        for sourceURL in urlsToMove {
            // Don't move into itself or same directory
            let sourceParent = sourceURL.deletingLastPathComponent().standardizedFileURL
            if sourceParent == destinationDir.standardizedFileURL {
                continue
            }
            // Don't move a folder into its own subtree
            if destinationDir.standardizedFileURL.path.hasPrefix(sourceURL.standardizedFileURL.path + "/") {
                continue
            }

            var destURL = destinationDir.appendingPathComponent(sourceURL.lastPathComponent)

            if fileManager.fileExists(atPath: destURL.path) {
                let alert = NSAlert()
                alert.messageText = languageManager.local("item_exists_title")
                alert.informativeText = String(format: languageManager.local("item_exists_message"), sourceURL.lastPathComponent)
                alert.icon = NSWorkspace.shared.icon(forFile: destURL.path)
                alert.addButton(withTitle: languageManager.local("replace"))
                alert.addButton(withTitle: languageManager.local("keep_both"))
                alert.addButton(withTitle: languageManager.local("skip"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    do {
                        try fileManager.removeItem(at: destURL)
                    } catch {
                        errorMessage = "Error replacing: \(error.localizedDescription)"
                        continue
                    }
                } else if response == .alertSecondButtonReturn {
                    var counter = 2
                    let baseName = sourceURL.deletingPathExtension().lastPathComponent
                    let ext = sourceURL.pathExtension
                    while fileManager.fileExists(atPath: destURL.path) {
                        let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
                        destURL = destinationDir.appendingPathComponent(newName)
                        counter += 1
                    }
                } else {
                    continue
                }
            }

            do {
                try fileManager.moveItem(at: sourceURL, to: destURL)
                affectedDirectories.insert(sourceURL.deletingLastPathComponent())
                movedCount += 1
                lastName = sourceURL.lastPathComponent
            } catch {
                errorMessage = "Error moving: \(error.localizedDescription)"
            }
        }

        loadDirectory()
        postFileSystemChange(for: Array(affectedDirectories))

        if movedCount == 1 {
            postStatus(String(format: languageManager.local("moved_singular"), lastName, destinationDir.lastPathComponent))
        } else if movedCount > 1 {
            postStatus(String(format: languageManager.local("moved_plural"), movedCount, destinationDir.lastPathComponent))
        }
    }

    func copyItems(_ items: [FileItem]) {
        clipboardService.clipboard = (items.map { $0.url }, .copy)
        let count = items.count
        if count == 1 {
            postStatus(String(format: languageManager.local("copied_singular"), items[0].name))
        } else {
            postStatus(String(format: languageManager.local("copied_plural"), count))
        }
    }

    func cutItems(_ items: [FileItem]) {
        let nonProtectedItems = items.filter { !$0.isSystemProtected }
        guard !nonProtectedItems.isEmpty else { return }
        clipboardService.clipboard = (nonProtectedItems.map { $0.url }, .cut)
        let count = nonProtectedItems.count
        if count == 1 {
            postStatus(String(format: languageManager.local("cut_singular"), nonProtectedItems[0].name))
        } else {
            postStatus(String(format: languageManager.local("cut_plural"), count))
        }
    }

    func pasteItems() {
        guard let clipboardItem = clipboardService.clipboard else { return }
        let count = clipboardItem.urls.count
        let actionLabel = clipboardItem.action == .copy ? languageManager.local("pasting") : languageManager.local("moving")
        if count == 1 {
            postStatus(String(format: languageManager.local("pasting_singular"), actionLabel, clipboardItem.urls[0].lastPathComponent), autoClear: false)
        } else {
            postStatus(String(format: languageManager.local("pasting_plural"), actionLabel, count), autoClear: false)
        }
        isProcessing = true
        var affectedDirectories: Set<URL> = [currentDirectory]
        var processedCount = 0
        var lastProcessedName = ""

        for sourceURL in clipboardItem.urls {
            var destinationURL = currentDirectory.appendingPathComponent(sourceURL.lastPathComponent)

            if sourceURL == destinationURL, clipboardItem.action == .cut {
                continue
            }

            var skipThisItem = false
            if fileManager.fileExists(atPath: destinationURL.path) {
                let alert = NSAlert()
                alert.messageText = languageManager.local("item_exists_title")
                alert.informativeText = String(format: languageManager.local("item_exists_message"), sourceURL.lastPathComponent)
                alert.icon = NSWorkspace.shared.icon(forFile: destinationURL.path)
                alert.addButton(withTitle: languageManager.local("replace"))
                alert.addButton(withTitle: languageManager.local("keep_both"))
                alert.addButton(withTitle: languageManager.local("skip"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    // Replace
                    do {
                        try fileManager.removeItem(at: destinationURL)
                    } catch {
                        errorMessage = "Erro ao substituir: \(error.localizedDescription)"
                        skipThisItem = true
                    }
                } else if response == .alertSecondButtonReturn {
                    // Keep both
                    var counter = 2
                    let baseName = sourceURL.deletingPathExtension().lastPathComponent
                    let ext = sourceURL.pathExtension
                    while fileManager.fileExists(atPath: destinationURL.path) {
                        let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
                        destinationURL = currentDirectory.appendingPathComponent(newName)
                        counter += 1
                    }
                } else {
                    // Skip
                    skipThisItem = true
                }
            }

            if skipThisItem {
                continue
            }

            do {
                if clipboardItem.action == .copy {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                } else if clipboardItem.action == .cut {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                    affectedDirectories.insert(sourceURL.deletingLastPathComponent())
                }
                processedCount += 1
                lastProcessedName = sourceURL.lastPathComponent
            } catch {
                errorMessage = "Erro ao colar: \(error.localizedDescription)"
            }
        }

        if clipboardItem.action == .cut {
            clipboardService.clipboard = nil
        }
        isProcessing = false
        loadDirectory()
        postFileSystemChange(for: Array(affectedDirectories))
        let doneLabel = clipboardItem.action == .copy ? languageManager.local("pasted") : languageManager.local("moved")
        if processedCount == 1 {
            postStatus(String(format: languageManager.local("paste_success_singular"), lastProcessedName, doneLabel))
        } else if processedCount > 1 {
            postStatus(String(format: languageManager.local("paste_success_plural"), processedCount, doneLabel))
        } else {
            statusMessage = nil
        }
    }

    func openInTerminal(url: URL? = nil) {
        let targetURL = url ?? currentDirectory
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", targetURL.path]
        try? process.run()
    }

    var canGoBack: Bool {
        historyIndex > 0
    }

    var canGoForward: Bool {
        historyIndex < navigationHistory.count - 1
    }

    var canGoToParent: Bool {
        currentDirectory.path != "/"
    }

    private func startTagSearch(_ tag: FinderTag) {
        stopTagSearch()

        isProcessing = true
        statusMessage = String(format: languageManager.local("searching_tag"), languageManager.local(tag.rawValue))

        metadataQuery = NSMetadataQuery()
        metadataQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        // Search using the localized Portuguese name for compatibility with standard macOS tags
        metadataQuery.predicate = NSPredicate(format: "kMDItemUserTags == %@", tag.localizedPortugueseName)

        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSearchResults()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery,
            queue: .main,
            using: handler
        )

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: metadataQuery,
            queue: .main,
            using: handler
        )

        metadataQuery.start()
    }

    private func stopTagSearch() {
        metadataQuery.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: metadataQuery)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: metadataQuery)
    }

    private func updateSearchResults() {
        // Guard against late notifications to avoid overwriting current navigation with old results.
        guard searchTag != nil else { return }
        let results = metadataQuery.results as? [NSMetadataItem] ?? []
        let items = results.compactMap { item -> FileItem? in
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return FileItem(url: URL(fileURLWithPath: path))
        }

        files = items.sorted { $0.name.lowercased() < $1.name.lowercased() }
        isProcessing = false
        if files.isEmpty {
            postStatus(languageManager.local("no_tag_results"))
        } else {
            statusMessage = nil
        }
    }

    func setTag(_ tag: FinderTag, on items: [FileItem]) {
        for item in items {
            var currentTags = FinderTag.tagsForURL(item.url)
            if !currentTags.contains(tag) {
                currentTags.append(tag)
            }
            try? FinderTag.setTags(currentTags, on: item.url)
        }
        loadDirectory()
        let count = items.count
        if count == 1 {
            postStatus(String(format: languageManager.local("tag_added_singular"), languageManager.local(tag.rawValue), items[0].name))
        } else {
            postStatus(String(format: languageManager.local("tag_added_plural"), languageManager.local(tag.rawValue), count))
        }
    }

    func removeTag(_ tag: FinderTag, from items: [FileItem]) {
        for item in items {
            var currentTags = FinderTag.tagsForURL(item.url)
            currentTags.removeAll { $0 == tag }
            try? FinderTag.setTags(currentTags, on: item.url)
        }
        loadDirectory()
        let count = items.count
        if count == 1 {
            postStatus(String(format: languageManager.local("tag_removed_singular"), languageManager.local(tag.rawValue), items[0].name))
        } else {
            postStatus(String(format: languageManager.local("tag_removed_plural"), languageManager.local(tag.rawValue), count))
        }
    }

    func removeAllTags(from items: [FileItem]) {
        for item in items {
            try? FinderTag.setTags([], on: item.url)
        }
        loadDirectory()
        let count = items.count
        if count == 1 {
            postStatus(String(format: languageManager.local("all_tags_removed_singular"), items[0].name))
        } else {
            postStatus(String(format: languageManager.local("all_tags_removed_plural"), count))
        }
    }

    // MARK: - Favorites

    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let urls = try? JSONDecoder().decode([URL].self, from: data)
        {
            favorites = urls
        } else {
            // Start empty as requested
            favorites = []
            saveFavorites()
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    func addToFavorites(_ url: URL) {
        if !favorites.contains(url) {
            favorites.append(url)
            saveFavorites()
            postStatus(String(format: languageManager.local("added_to_favorites"), url.lastPathComponent))
        }
    }

    func removeFromFavorites(_ url: URL) {
        if let index = favorites.firstIndex(of: url) {
            favorites.remove(at: index)
            saveFavorites()
            postStatus(String(format: languageManager.local("removed_from_favorites"), url.lastPathComponent))
        }
    }

    func isFavorite(_ url: URL) -> Bool {
        favorites.contains(url)
    }

    func isSystemProtected(url: URL) -> Bool {
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
}
