//
//  FileListView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import AppKit
import QuickLook
import QuickLookThumbnailing
import SwiftUI

enum ViewMode {
    case list
    case icons
}

struct FileListView: View {
    @ObservedObject var fileManager: FileManagerService
    @State private var viewMode: ViewMode = .list
    @State private var showingCreateFolder = false
    @State private var showingCreateFile = false
    @State private var newFolderName = ""
    @State private var newFileName = ""
    @State private var editingItem: FileItem?
    @State private var newItemName = ""
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var lastSelectedID: UUID?
    @FocusState private var isListFocused: Bool
    @State private var sortOrder = [KeyPathComparator(\FileItem.name)]
    @State private var itemToDelete: FileItem?
    @State private var previewURL: URL?

    var sortedFiles: [FileItem] {
        fileManager.files.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: { fileManager.navigateBack() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!fileManager.canGoBack)

                Button(action: { fileManager.navigateForward() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!fileManager.canGoForward)

                Button(action: { fileManager.navigateToParent() }) {
                    Image(systemName: "arrow.up")
                }
                .disabled(!fileManager.canGoToParent)

                Spacer()

                Picker("View Mode", selection: $viewMode) {
                    Image(systemName: "list.bullet")
                        .tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2")
                        .tag(ViewMode.icons)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .frame(width: 80)

                Button(action: { fileManager.pasteItem() }) {
                    Image(systemName: "doc.on.clipboard")
                }
                .disabled(fileManager.clipboard == nil)
                .help("Colar")

                Button(action: { fileManager.showHiddenFiles.toggle() }) {
                    Image(systemName: fileManager.showHiddenFiles ? "eye" : "eye.slash")
                }
                .help(fileManager.showHiddenFiles ? "Ocultar arquivos ocultos" : "Mostrar arquivos ocultos")

                Button(action: { showingCreateFolder = true }) {
                    Image(systemName: "folder.badge.plus")
                }

                Button(action: { showingCreateFile = true }) {
                    Image(systemName: "doc.badge.plus")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            // File list
            if viewMode == .list {
                listView
            } else {
                iconView
            }
        }
        .sheet(isPresented: $showingCreateFolder) {
            CreateFolderSheet(isPresented: $showingCreateFolder, folderName: $newFolderName) {
                fileManager.createFolder(name: newFolderName)
                newFolderName = ""
            }
        }
        .sheet(isPresented: $showingCreateFile) {
            CreateFileSheet(isPresented: $showingCreateFile, fileName: $newFileName) {
                fileManager.createFile(name: newFileName)
                newFileName = ""
            }
        }
        .alert("Erro", isPresented: Binding<Bool>(
            get: { fileManager.errorMessage != nil },
            set: { if !$0 { fileManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = fileManager.errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog(
            "Mover para a Lixeira",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mover para Lixeira", role: .destructive) {
                if let item = itemToDelete {
                    fileManager.deleteItem(item)
                }
                itemToDelete = nil
            }
            Button("Cancelar", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("Tem certeza de que deseja mover '\(item.name)' para a Lixeira?")
            }
        }
        .quickLookPreview($previewURL)
        .focusable()
        .focusEffectDisabled()
        .focused($isListFocused)
        .onAppear {
            isListFocused = true
        }
        .onKeyPress { keyPress in
            if editingItem != nil || showingCreateFolder || showingCreateFile { return .ignored }

            if keyPress.characters == " " {
                if let currentId = selectedFileIDs.first, let item = sortedFiles.first(where: { $0.id == currentId }) {
                    previewURL = item.url
                    return .handled
                }
                return .ignored
            }

            guard keyPress.modifiers.isEmpty, let char = keyPress.characters.first, char.isLetter || char.isNumber else { return .ignored }

            let prefix = String(char).lowercased()
            let currentSortedFiles = sortedFiles
            guard !currentSortedFiles.isEmpty else { return .ignored }

            var startIndex = 0
            if let currentId = selectedFileIDs.first, let currentIndex = currentSortedFiles.firstIndex(where: { $0.id == currentId }) {
                startIndex = currentIndex + 1
            }

            for i in startIndex ..< currentSortedFiles.count {
                if currentSortedFiles[i].name.lowercased().hasPrefix(prefix) {
                    selectedFileIDs = [currentSortedFiles[i].id]
                    lastSelectedID = currentSortedFiles[i].id
                    return .handled
                }
            }

            for i in 0 ..< startIndex {
                if currentSortedFiles[i].name.lowercased().hasPrefix(prefix) {
                    selectedFileIDs = [currentSortedFiles[i].id]
                    lastSelectedID = currentSortedFiles[i].id
                    return .handled
                }
            }

            return .ignored
        }
    }

    var listView: some View {
        Table(sortedFiles, selection: $selectedFileIDs, sortOrder: $sortOrder) {
            TableColumn("Nome", value: \.name) { item in
                HStack(spacing: 8) {
                    FileIconView(item: item, size: CGSize(width: 16, height: 16))
                        .foregroundColor(.accentColor)
                    if editingItem == item {
                        TextField("Nome", text: $newItemName)
                            .onSubmit {
                                if !newItemName.isEmpty {
                                    fileManager.renameItem(item, to: newItemName)
                                }
                                editingItem = nil
                                newItemName = ""
                            }
                            .onAppear {
                                newItemName = item.name
                            }
                    } else {
                        Text(item.name)
                    }
                }
            }

            TableColumn("Data", value: \.modificationDate) { item in
                Text(item.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .width(min: 120, max: 150)

            TableColumn("Tamanho", value: \.fileSize) { item in
                Text(item.formattedSize)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .width(min: 80, max: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: UUID.self) { items in
            if let id = items.first, let item = fileManager.files.first(where: { $0.id == id }) {
                Button(action: {
                    if item.isDirectory {
                        fileManager.navigateTo(item.url)
                    } else {
                        NSWorkspace.shared.open(item.url)
                    }
                }) {
                    Label("Abrir", systemImage: "arrow.right.circle")
                }
                Button(action: { editingItem = item }) {
                    Label("Renomear", systemImage: "pencil")
                }
                if item.isDirectory {
                    Button(action: { fileManager.openInTerminal(url: item.url) }) {
                        Label("Abrir no Terminal", systemImage: "terminal")
                    }
                }
                Button(action: { fileManager.copyItem(item) }) {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                Button(action: { fileManager.cutItem(item) }) {
                    Label("Recortar", systemImage: "scissors")
                }
                Divider()
                Button(action: { fileManager.compressItem(item) }) {
                    Label("Comprimir", systemImage: "archivebox")
                }
                Divider()
                Button(action: { itemToDelete = item }) {
                    Label("Mover para Lixeira", systemImage: "trash")
                }
            }
        } primaryAction: { items in
            if let id = items.first, let item = fileManager.files.first(where: { $0.id == id }) {
                if item.isDirectory {
                    fileManager.navigateTo(item.url)
                } else {
                    NSWorkspace.shared.open(item.url)
                }
            }
        }
        .contextMenu {
            Button(action: { showingCreateFolder = true }) {
                Label("Nova Pasta", systemImage: "folder.badge.plus")
            }
            Button(action: { showingCreateFile = true }) {
                Label("Novo Arquivo", systemImage: "doc.badge.plus")
            }
            Divider()

            Button(action: { fileManager.pasteItem() }) {
                Label("Colar", systemImage: "doc.on.clipboard")
            }
            .disabled(fileManager.clipboard == nil)

            Button(action: { fileManager.openInTerminal() }) {
                Label("Abrir no Terminal", systemImage: "terminal")
            }
        }
    }

    var iconView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100), spacing: 16),
            ], spacing: 16) {
                ForEach(sortedFiles) { item in
                    VStack(spacing: 8) {
                        FileIconView(item: item, size: CGSize(width: 56, height: 56))
                            .foregroundColor(.accentColor)
                        Text(item.name)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 100)
                    }
                    .padding(12)
                    .background(selectedFileIDs.contains(item.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture(count: 2) {
                        if item.isDirectory {
                            fileManager.navigateTo(item.url)
                        } else {
                            NSWorkspace.shared.open(item.url)
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                                if selectedFileIDs.contains(item.id) {
                                    selectedFileIDs.remove(item.id)
                                } else {
                                    selectedFileIDs.insert(item.id)
                                }
                                lastSelectedID = item.id
                            } else if NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
                                      let lastId = lastSelectedID,
                                      let lastIndex = sortedFiles.firstIndex(where: { $0.id == lastId }),
                                      let currentIndex = sortedFiles.firstIndex(where: { $0.id == item.id })
                            {
                                let range = min(lastIndex, currentIndex) ... max(lastIndex, currentIndex)
                                selectedFileIDs.formUnion(sortedFiles[range].map { $0.id })
                            } else {
                                selectedFileIDs = [item.id]
                                lastSelectedID = item.id
                            }
                        }
                    )
                    .contextMenu {
                        Button(action: {
                            if item.isDirectory {
                                fileManager.navigateTo(item.url)
                            } else {
                                NSWorkspace.shared.open(item.url)
                            }
                        }) {
                            Label("Abrir", systemImage: "arrow.right.circle")
                        }
                        Button(action: { editingItem = item }) {
                            Label("Renomear", systemImage: "pencil")
                        }
                        if item.isDirectory {
                            Button(action: { fileManager.openInTerminal(url: item.url) }) {
                                Label("Abrir no Terminal", systemImage: "terminal")
                            }
                        }
                        Button(action: { fileManager.copyItem(item) }) {
                            Label("Copiar", systemImage: "doc.on.doc")
                        }
                        Button(action: { fileManager.cutItem(item) }) {
                            Label("Recortar", systemImage: "scissors")
                        }
                        Divider()
                        Button(action: { fileManager.compressItem(item) }) {
                            Label("Comprimir", systemImage: "archivebox")
                        }
                        Divider()
                        Button(action: { itemToDelete = item }) {
                            Label("Mover para Lixeira", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
        .contextMenu {
            Button(action: { showingCreateFolder = true }) {
                Label("Nova Pasta", systemImage: "folder.badge.plus")
            }
            Button(action: { showingCreateFile = true }) {
                Label("Novo Arquivo", systemImage: "doc.badge.plus")
            }
            Divider()

            Button(action: { fileManager.pasteItem() }) {
                Label("Colar", systemImage: "doc.on.clipboard")
            }
            .disabled(fileManager.clipboard == nil)

            Button(action: { fileManager.openInTerminal() }) {
                Label("Abrir no Terminal", systemImage: "terminal")
            }
        }
    }
}

struct CreateFolderSheet: View {
    @Binding var isPresented: Bool
    @Binding var folderName: String
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Nova Pasta")
                .font(.headline)

            TextField("Nome da pasta", text: $folderName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancelar") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Criar") {
                    onCreate()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

struct CreateFileSheet: View {
    @Binding var isPresented: Bool
    @Binding var fileName: String
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Novo Arquivo")
                .font(.headline)

            TextField("Nome do arquivo", text: $fileName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancelar") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Criar") {
                    onCreate()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fileName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

struct FileIconView: View {
    let item: FileItem
    let size: CGSize

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                item.icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        guard !item.isDirectory else { return }

        let ext = item.url.pathExtension.lowercased()
        let supportedExtensions = ["png", "jpg", "jpeg", "gif", "heic", "webp", "pdf", "mp4", "mov"]
        guard supportedExtensions.contains(ext) else { return }

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            if let nsImage = rep?.nsImage {
                DispatchQueue.main.async {
                    self.thumbnail = nsImage
                }
            }
        }
    }
}

#Preview {
    FileListView(fileManager: FileManagerService())
}
