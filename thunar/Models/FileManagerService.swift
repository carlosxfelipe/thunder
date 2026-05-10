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
    enum ClipboardAction {
        case copy
        case cut
    }

    @Published var clipboard: (urls: [URL], action: ClipboardAction)? = nil
    @Published var errorMessage: String? = nil
    @Published var showHiddenFiles: Bool = false {
        didSet {
            loadDirectory()
        }
    }

    private let fileManager = FileManager.default

    init() {
        let home = fileManager.homeDirectoryForCurrentUser
        currentDirectory = home
        navigationHistory.append(home)
        historyIndex = 0
        loadDirectory()
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
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
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
        } catch {
            errorMessage = "Erro ao excluir: \(error.localizedDescription)"
        }
    }

    func compressItem(_ item: FileItem) {
        let currentDir = currentDirectory

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
                    self.loadDirectory()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Erro ao comprimir: \(error.localizedDescription)"
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
        } catch {
            print("Error renaming item: \(error)")
        }
    }

    func copyItems(_ items: [FileItem]) {
        clipboard = (items.map { $0.url }, .copy)
    }

    func cutItems(_ items: [FileItem]) {
        clipboard = (items.map { $0.url }, .cut)
    }

    func pasteItems() {
        guard let clipboardItem = clipboard else { return }

        for sourceURL in clipboardItem.urls {
            var destinationURL = currentDirectory.appendingPathComponent(sourceURL.lastPathComponent)

            // Se for mover (recortar) para o mesmo lugar exato, não fazemos nada
            if sourceURL == destinationURL, clipboardItem.action == .cut {
                continue
            }

            // Se o arquivo já existe na pasta de destino (ou estamos copiando pro mesmo lugar), geramos um novo nome
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
            clipboard = nil // Limpa após mover
        }
        loadDirectory()
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
}
