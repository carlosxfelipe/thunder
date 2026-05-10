//
//  FileManagerService.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import Combine
import Foundation
import SwiftUI

@MainActor
class FileManagerService: ObservableObject {
    @Published var currentDirectory: URL
    @Published var files: [FileItem] = []
    @Published var selectedFiles: Set<FileItem> = []
    @Published var navigationHistory: [URL] = []
    @Published var historyIndex: Int = 0
    private let clipboardService = ClipboardService.shared

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

    private let fileManager = FileManager.default

    init() {
        let home = fileManager.homeDirectoryForCurrentUser
        currentDirectory = home
        navigationHistory.append(home)
        historyIndex = 0
        loadDirectory()
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
        let targetURL = url ?? currentDirectory

        Task {
            do {
                var options: FileManager.DirectoryEnumerationOptions = []
                if !self.showHiddenFiles {
                    options.insert(.skipsHiddenFiles)
                }

                let contents = try fileManager.contentsOfDirectory(
                    at: targetURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey],
                    options: options
                )

                // Processamento pesado (mapeamento e ordenação) em uma thread separada para não travar a UI
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
                    self.errorMessage = "Acesso Negado (Proteção do macOS).\n\nPara acessar a Lixeira ou pastas protegidas do sistema, vá em:\nAjustes do Sistema > Privacidade e Segurança > Acesso Total ao Disco\ne conceda permissão para o seu aplicativo (ou para o Xcode/Terminal)."
                } else {
                    self.errorMessage = "Não foi possível acessar a pasta.\nDetalhes: \(error.localizedDescription)"
                }
            }
        }
    }

    func navigateTo(_ url: URL) {
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
        historyIndex -= 1
        let url = navigationHistory[historyIndex]
        loadDirectory(url)
    }

    func navigateForward() {
        guard historyIndex < navigationHistory.count - 1 else { return }
        historyIndex += 1
        let url = navigationHistory[historyIndex]
        loadDirectory(url)
    }

    func navigateToParent() {
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
            errorMessage = "Já existe um item com o nome '\(name)' neste local."
            return
        }

        do {
            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
            loadDirectory()
        } catch {
            errorMessage = "Erro ao criar pasta: \(error.localizedDescription)"
        }
    }

    func createFile(name: String) {
        let newFileURL = currentDirectory.appendingPathComponent(name)

        if fileManager.fileExists(atPath: newFileURL.path) {
            errorMessage = "Já existe um item com o nome '\(name)' neste local."
            return
        }

        if fileManager.createFile(atPath: newFileURL.path, contents: nil) {
            loadDirectory()
        } else {
            errorMessage = "Não foi possível criar o arquivo."
        }
    }

    func deleteItem(_ item: FileItem) {
        do {
            try fileManager.trashItem(at: item.url, resultingItemURL: nil)
            loadDirectory()
            postStatus("\"\(item.name)\" movido para a Lixeira")
        } catch {
            errorMessage = "Erro ao excluir: \(error.localizedDescription)"
        }
    }

    func permanentDeleteItem(_ item: FileItem) {
        do {
            try fileManager.removeItem(at: item.url)
            loadDirectory()
            postStatus("\"\(item.name)\" excluído permanentemente")
        } catch {
            errorMessage = "Erro ao excluir: \(error.localizedDescription)"
        }
    }

    func compressItem(_ item: FileItem) {
        let currentDir = currentDirectory
        isProcessing = true
        postStatus("Comprimindo \"\(item.name)\"...", autoClear: false)

        Task.detached {
            var zipName = item.name + ".zip"
            var zipURL = currentDir.appendingPathComponent(zipName)
            var counter = 2

            while FileManager.default.fileExists(atPath: zipURL.path) {
                zipName = "\(item.name) \(counter).zip"
                zipURL = currentDir.appendingPathComponent(zipName)
                counter += 1
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", item.url.path, zipURL.path]

            do {
                try process.run()
                process.waitUntilExit()

                await MainActor.run {
                    self.isProcessing = false
                    self.loadDirectory()
                    self.postStatus("\"\(item.name)\" comprimido com sucesso")
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

    func deleteSelectedItems() {
        for item in selectedFiles {
            deleteItem(item)
        }
    }

    func renameItem(_ item: FileItem, to newName: String) {
        let newURL = currentDirectory.appendingPathComponent(newName)

        do {
            try fileManager.moveItem(at: item.url, to: newURL)
            loadDirectory()
            postStatus("\"\(item.name)\" renomeado para \"\(newName)\"")
        } catch {
            print("Error renaming item: \(error)")
        }
    }

    func copyItems(_ items: [FileItem]) {
        clipboardService.clipboard = (items.map { $0.url }, .copy)
        let count = items.count
        postStatus(count == 1 ? "\"\(items[0].name)\" copiado" : "\(count) itens copiados")
    }

    func cutItems(_ items: [FileItem]) {
        clipboardService.clipboard = (items.map { $0.url }, .cut)
        let count = items.count
        postStatus(count == 1 ? "\"\(items[0].name)\" recortado" : "\(count) itens recortados")
    }

    func pasteItems() {
        guard let clipboardItem = clipboardService.clipboard else { return }
        let count = clipboardItem.urls.count
        let actionLabel = clipboardItem.action == .copy ? "Colando" : "Movendo"
        postStatus(count == 1 ? "\(actionLabel) \"\(clipboardItem.urls[0].lastPathComponent)\"..." : "\(actionLabel) \(count) itens...", autoClear: false)
        isProcessing = true

        for sourceURL in clipboardItem.urls {
            var destinationURL = currentDirectory.appendingPathComponent(sourceURL.lastPathComponent)

            if sourceURL == destinationURL, clipboardItem.action == .cut {
                continue
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                var counter = 2
                let baseName = sourceURL.deletingPathExtension().lastPathComponent
                let ext = sourceURL.pathExtension
                while fileManager.fileExists(atPath: destinationURL.path) {
                    let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
                    destinationURL = currentDirectory.appendingPathComponent(newName)
                    counter += 1
                }
            }

            do {
                if clipboardItem.action == .copy {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                } else if clipboardItem.action == .cut {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                errorMessage = "Erro ao colar: \(error.localizedDescription)"
            }
        }

        if clipboardItem.action == .cut {
            clipboardService.clipboard = nil
        }
        isProcessing = false
        loadDirectory()
        let doneLabel = clipboardItem.action == .copy ? "colado" : "movido"
        postStatus(count == 1 ? "\"\(clipboardItem.urls[0].lastPathComponent)\" \(doneLabel) com sucesso" : "\(count) itens \(doneLabel)s com sucesso")
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
        statusMessage = "Buscando itens com etiqueta \"\(tag.rawValue)\"..."

        metadataQuery = NSMetadataQuery()
        metadataQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        metadataQuery.predicate = NSPredicate(format: "kMDItemUserTags == %@", tag.rawValue)

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
        // Guard contra notificações que chegam depois do usuário ter saído da busca por etiqueta
        // (evita sobrescrever a navegação atual com resultados antigos da query).
        guard searchTag != nil else { return }
        let results = metadataQuery.results as? [NSMetadataItem] ?? []
        let items = results.compactMap { item -> FileItem? in
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return FileItem(url: URL(fileURLWithPath: path))
        }

        files = items.sorted { $0.name.lowercased() < $1.name.lowercased() }
        isProcessing = false
        if files.isEmpty {
            postStatus("Nenhum item encontrado com esta etiqueta")
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
        postStatus(count == 1 ? "Etiqueta \"\(tag.rawValue)\" adicionada a \"\(items[0].name)\"" : "Etiqueta \"\(tag.rawValue)\" adicionada a \(count) itens")
    }

    func removeTag(_ tag: FinderTag, from items: [FileItem]) {
        for item in items {
            var currentTags = FinderTag.tagsForURL(item.url)
            currentTags.removeAll { $0 == tag }
            try? FinderTag.setTags(currentTags, on: item.url)
        }
        loadDirectory()
        let count = items.count
        postStatus(count == 1 ? "Etiqueta \"\(tag.rawValue)\" removida de \"\(items[0].name)\"" : "Etiqueta \"\(tag.rawValue)\" removida de \(count) itens")
    }

    func removeAllTags(from items: [FileItem]) {
        for item in items {
            try? FinderTag.setTags([], on: item.url)
        }
        loadDirectory()
        let count = items.count
        postStatus(count == 1 ? "Etiquetas removidas de \"\(items[0].name)\"" : "Etiquetas removidas de \(count) itens")
    }
}
