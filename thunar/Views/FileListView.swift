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

enum ViewMode: String {
    case list
    case icons
}

struct FileListView: View {
    @ObservedObject var fileManager: FileManagerService
    @ObservedObject private var clipboardService = ClipboardService.shared
    @AppStorage("viewMode") private var viewMode: ViewMode = .list
    @State private var showingCreateFolder = false
    @State private var showingCreateFile = false
    @State private var newFolderName = ""
    @State private var newFileName = ""
    @State private var editingItem: FileItem?
    @State private var newItemName = ""
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var lastSelectedID: UUID?
    @State private var selectionAnchorID: UUID?
    @State private var gridWidth: CGFloat = 600
    @State private var sortOrder = [KeyPathComparator(\FileItem.name)]
    @State private var itemsToDelete: [FileItem] = []
    @State private var infoItem: FileItem?
    @State private var previewURL: URL?
    @State private var selectionRectStart: CGPoint? = nil
    @State private var selectionRectEnd: CGPoint? = nil
    @State private var searchText = ""
    @FocusState private var isListFocused: Bool
    @FocusState private var isSearchFocused: Bool

    var sortedFiles: [FileItem] {
        fileManager.files.sorted(using: sortOrder)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func locationText(for item: FileItem) -> String {
        let parentURL = item.url.deletingLastPathComponent()
        let rootPath = fileManager.currentDirectory.standardizedFileURL.path
        let parentPath = parentURL.standardizedFileURL.path

        if parentPath == rootPath {
            return "."
        }

        if parentPath.hasPrefix(rootPath + "/") {
            return String(parentPath.dropFirst(rootPath.count + 1))
        }

        return parentPath
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

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Buscar", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 220)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

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

                Button(action: { fileManager.pasteItems() }) {
                    Image(systemName: "doc.on.clipboard")
                }
                .disabled(clipboardService.clipboard == nil)
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

            if isSearching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    Text("Resultados em \(fileManager.currentDirectory.path)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(sortedFiles.count) \(sortedFiles.count == 1 ? "item" : "itens")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
            }

            if sortedFiles.isEmpty, isSearching, !fileManager.isProcessing {
                ContentUnavailableView(
                    "Nenhum item encontrado",
                    systemImage: "magnifyingglass",
                    description: Text("Tente buscar por outro nome.")
                )
            } else {
                if viewMode == .list {
                    listView
                } else {
                    iconView
                }
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
        .sheet(item: $editingItem) { item in
            RenameSheet(
                item: item,
                fileName: $newItemName,
                isPresented: Binding(
                    get: { editingItem != nil },
                    set: { if !$0 { editingItem = nil } }
                )
            ) {
                if !newItemName.isEmpty && newItemName != item.name {
                    fileManager.renameItem(item, to: newItemName)
                }
                editingItem = nil
                newItemName = ""
            }
            .onAppear {
                newItemName = item.name
            }
        }
        .sheet(item: $infoItem) { item in
            ItemInfoSheet(
                item: item,
                isPresented: Binding(
                    get: { infoItem != nil },
                    set: { if !$0 { infoItem = nil } }
                )
            )
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
            "Excluir Permanentemente",
            isPresented: Binding(
                get: { !itemsToDelete.isEmpty },
                set: { if !$0 { itemsToDelete = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Excluir", role: .destructive) {
                fileManager.permanentDeleteItems(itemsToDelete)
                itemsToDelete = []
            }
            Button("Cancelar", role: .cancel) {
                itemsToDelete = []
            }
        } message: {
            if itemsToDelete.count == 1, let item = itemsToDelete.first {
                Text("'\(item.name)' será apagado definitivamente. Esta ação não pode ser desfeita.")
            } else {
                Text("\(itemsToDelete.count) itens serão apagados definitivamente. Esta ação não pode ser desfeita.")
            }
        }
        .quickLookPreview($previewURL)
        .background(
            Group {
                Button(action: {
                    let items = sortedFiles.filter { selectedFileIDs.contains($0.id) }
                    if !items.isEmpty { fileManager.copyItems(items) }
                }) { EmptyView() }.keyboardShortcut("c", modifiers: .command)

                Button(action: {
                    let items = sortedFiles.filter { selectedFileIDs.contains($0.id) }
                    if !items.isEmpty { fileManager.cutItems(items) }
                }) { EmptyView() }.keyboardShortcut("x", modifiers: .command)

                Button(action: {
                    fileManager.pasteItems()
                }) { EmptyView() }.keyboardShortcut("v", modifiers: .command)

                Button(action: {
                    fileManager.showHiddenFiles.toggle()
                }) { EmptyView() }.keyboardShortcut(".", modifiers: [.command, .shift])

                Button(action: {
                    isSearchFocused = true
                }) { EmptyView() }.keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0)
        )
        .focusable()
        .focusEffectDisabled()
        .focused($isListFocused)
        .onAppear {
            isListFocused = true
        }
        .onChange(of: searchText) {
            fileManager.searchFiles(matching: searchText)
            let visibleIDs = Set(sortedFiles.map(\.id))
            selectedFileIDs = selectedFileIDs.intersection(visibleIDs)
            if let lastSelectedID, !visibleIDs.contains(lastSelectedID) {
                self.lastSelectedID = nil
            }
            if let selectionAnchorID, !visibleIDs.contains(selectionAnchorID) {
                self.selectionAnchorID = nil
            }
        }
        .onChange(of: fileManager.currentDirectory) {
            searchText = ""
        }
        .onKeyPress { keyPress in
            if editingItem != nil || showingCreateFolder || showingCreateFile { return .ignored }

            if keyPress.key == .escape, !searchText.isEmpty {
                searchText = ""
                isListFocused = true
                return .handled
            }

            if isSearchFocused {
                return .ignored
            }

            if keyPress.characters == " " {
                if let currentId = selectedFileIDs.first, let item = sortedFiles.first(where: { $0.id == currentId }) {
                    previewURL = item.url
                    return .handled
                }
                return .ignored
            }

            if keyPress.key == .return, viewMode == .icons {
                if let currentId = selectedFileIDs.first, let item = sortedFiles.first(where: { $0.id == currentId }) {
                    fileManager.openItem(item)
                    return .handled
                }
                return .ignored
            }

            if viewMode == .icons, [.leftArrow, .rightArrow, .upArrow, .downArrow].contains(keyPress.key) {
                let currentSortedFiles = sortedFiles
                guard !currentSortedFiles.isEmpty else { return .ignored }

                var currentIndex = 0
                if let lastId = lastSelectedID, let idx = currentSortedFiles.firstIndex(where: { $0.id == lastId }) {
                    currentIndex = idx
                }

                let columnsCount = max(1, Int((gridWidth - 16) / 116))
                let currentRow = currentIndex / columnsCount
                let currentCol = currentIndex % columnsCount
                let lastIndex = currentSortedFiles.count - 1
                var newIndex = currentIndex

                if keyPress.key == .leftArrow {
                    if currentCol > 0 {
                        newIndex = currentIndex - 1
                    }
                } else if keyPress.key == .rightArrow {
                    let rowStart = currentRow * columnsCount
                    let lastColInRow = min(columnsCount - 1, lastIndex - rowStart)
                    if currentCol < lastColInRow {
                        newIndex = currentIndex + 1
                    }
                } else if keyPress.key == .upArrow {
                    if currentRow > 0 {
                        newIndex = currentIndex - columnsCount
                    }
                } else if keyPress.key == .downArrow {
                    let candidate = currentIndex + columnsCount
                    if candidate <= lastIndex {
                        newIndex = candidate
                    }
                }

                if newIndex != currentIndex {
                    let newItem = currentSortedFiles[newIndex]
                    if keyPress.modifiers.contains(.shift) {
                        if let anchorId = selectionAnchorID,
                           let anchorIndex = currentSortedFiles.firstIndex(where: { $0.id == anchorId })
                        {
                            let startRow = anchorIndex / columnsCount
                            let startCol = anchorIndex % columnsCount
                            let endRow = newIndex / columnsCount
                            let endCol = newIndex % columnsCount

                            let minRow = min(startRow, endRow)
                            let maxRow = max(startRow, endRow)
                            let minCol = min(startCol, endCol)
                            let maxCol = max(startCol, endCol)

                            var boxIDs: Set<UUID> = []
                            for r in minRow ... maxRow {
                                for c in minCol ... maxCol {
                                    let idx = r * columnsCount + c
                                    if idx >= 0 && idx < currentSortedFiles.count {
                                        boxIDs.insert(currentSortedFiles[idx].id)
                                    }
                                }
                            }
                            selectedFileIDs = boxIDs
                        }
                    } else {
                        selectedFileIDs = [newItem.id]
                        selectionAnchorID = newItem.id
                    }
                    lastSelectedID = newItem.id
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
                    selectionAnchorID = currentSortedFiles[i].id
                    return .handled
                }
            }

            for i in 0 ..< startIndex {
                if currentSortedFiles[i].name.lowercased().hasPrefix(prefix) {
                    selectedFileIDs = [currentSortedFiles[i].id]
                    lastSelectedID = currentSortedFiles[i].id
                    selectionAnchorID = currentSortedFiles[i].id
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
                    Text(item.name)
                    if !item.tags.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(item.tags) { tag in
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
            }

            if isSearching {
                TableColumn("Local") { item in
                    Text(locationText(for: item))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.url.deletingLastPathComponent().path)
                }
                .width(min: 180, ideal: 260)
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
                    fileManager.openItem(item)
                }) {
                    Label("Abrir", systemImage: "arrow.right.circle")
                }
                Button(action: { editingItem = item }) {
                    Label("Renomear", systemImage: "pencil")
                }
                Button(action: { infoItem = item }) {
                    Label("Obter Informações", systemImage: "info.circle")
                }
                if item.isDirectory {
                    Button(action: { fileManager.openInTerminal(url: item.url) }) {
                        Label("Abrir no Terminal", systemImage: "terminal")
                    }
                }
                Button(action: {
                    let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                    fileManager.copyItems(items)
                }) {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                Button(action: {
                    let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                    fileManager.cutItems(items)
                }) {
                    Label("Recortar", systemImage: "scissors")
                }
                Divider()
                Button(action: { fileManager.compressItem(item) }) {
                    Label("Comprimir", systemImage: "archivebox")
                }
                Divider()
                Menu {
                    ForEach(FinderTag.allCases) { tag in
                        Button(action: {
                            let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                            if item.tags.contains(tag) {
                                fileManager.removeTag(tag, from: items)
                            } else {
                                fileManager.setTag(tag, on: items)
                            }
                        }) {
                            HStack {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 10, height: 10)
                                Text(tag.rawValue)
                                if item.tags.contains(tag) {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    if !item.tags.isEmpty {
                        Divider()
                        Button(action: {
                            let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                            fileManager.removeAllTags(from: items)
                        }) {
                            Label("Remover Todas", systemImage: "xmark")
                        }
                    }
                } label: {
                    Label("Etiquetas", systemImage: "tag")
                }
                Divider()
                Button(action: {
                    fileManager.deleteItems(contextItems(for: item))
                }) {
                    Label("Mover para Lixeira", systemImage: "trash")
                }
                Button(role: .destructive, action: {
                    itemsToDelete = contextItems(for: item)
                }) {
                    Label("Excluir Permanentemente", systemImage: "xmark.bin")
                }
            }
        } primaryAction: { items in
            if let id = items.first, let item = fileManager.files.first(where: { $0.id == id }) {
                fileManager.openItem(item)
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

            Button(action: { fileManager.pasteItems() }) {
                Label("Colar", systemImage: "doc.on.clipboard")
            }
            .disabled(clipboardService.clipboard == nil)

            Button(action: { fileManager.openInTerminal() }) {
                Label("Abrir no Terminal", systemImage: "terminal")
            }
        }
    }

    var iconView: some View {
        GeometryReader { geo in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Background for deselection and marquee start
                    Color.white.opacity(0.0001)
                        .frame(minHeight: geo.size.height)
                        .onTapGesture {
                            selectedFileIDs = []
                            selectionAnchorID = nil
                            lastSelectedID = nil
                        }
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    if selectionRectStart == nil {
                                        selectionRectStart = value.startLocation
                                    }
                                    selectionRectEnd = value.location
                                    updateSelectionFromMarquee()
                                }
                                .onEnded { _ in
                                    selectionRectStart = nil
                                    selectionRectEnd = nil
                                }
                        )

                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100), spacing: 16),
                    ], spacing: 16) {
                        ForEach(sortedFiles) { item in
                            VStack(spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    FileIconView(item: item, size: CGSize(width: 56, height: 56))
                                        .foregroundColor(.accentColor)
                                    if !item.tags.isEmpty {
                                        HStack(spacing: 1) {
                                            ForEach(item.tags) { tag in
                                                Circle()
                                                    .fill(tag.color)
                                                    .frame(width: 8, height: 8)
                                            }
                                        }
                                        .offset(x: 4, y: -2)
                                    }
                                }
                                Text(item.name)
                                    .font(.system(size: 11))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 100)
                                if isSearching {
                                    Text(locationText(for: item))
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: 100)
                                }
                            }
                            .padding(12)
                            .background(selectedFileIDs.contains(item.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                            .onTapGesture(count: 2) {
                                fileManager.openItem(item)
                            }
                            .simultaneousGesture(
                                TapGesture().modifiers(.shift).onEnded {
                                    selectRange(to: item)
                                }
                            )
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                                        if selectedFileIDs.contains(item.id) {
                                            selectedFileIDs.remove(item.id)
                                        } else {
                                            selectedFileIDs.insert(item.id)
                                        }
                                        lastSelectedID = item.id
                                    } else {
                                        selectedFileIDs = [item.id]
                                        lastSelectedID = item.id
                                        selectionAnchorID = item.id
                                    }
                                }
                            )
                            .contextMenu {
                                // ... (context menu items remain same)
                                Button(action: {
                                    fileManager.openItem(item)
                                }) {
                                    Label("Abrir", systemImage: "arrow.right.circle")
                                }
                                Button(action: { editingItem = item }) {
                                    Label("Renomear", systemImage: "pencil")
                                }
                                Button(action: { infoItem = item }) {
                                    Label("Obter Informações", systemImage: "info.circle")
                                }
                                if item.isDirectory {
                                    Button(action: { fileManager.openInTerminal(url: item.url) }) {
                                        Label("Abrir no Terminal", systemImage: "terminal")
                                    }
                                }
                                Button(action: {
                                    let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                                    fileManager.copyItems(items)
                                }) {
                                    Label("Copiar", systemImage: "doc.on.doc")
                                }
                                Button(action: {
                                    let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                                    fileManager.cutItems(items)
                                }) {
                                    Label("Recortar", systemImage: "scissors")
                                }
                                Divider()
                                Button(action: { fileManager.compressItem(item) }) {
                                    Label("Comprimir", systemImage: "archivebox")
                                }
                                Divider()
                                Menu {
                                    ForEach(FinderTag.allCases) { tag in
                                        Button(action: {
                                            let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                                            if item.tags.contains(tag) {
                                                fileManager.removeTag(tag, from: items)
                                            } else {
                                                fileManager.setTag(tag, on: items)
                                            }
                                        }) {
                                            HStack {
                                                Circle()
                                                    .fill(tag.color)
                                                    .frame(width: 10, height: 10)
                                                Text(tag.rawValue)
                                                if item.tags.contains(tag) {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                    if !item.tags.isEmpty {
                                        Divider()
                                        Button(action: {
                                            let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                                            fileManager.removeAllTags(from: items)
                                        }) {
                                            Label("Remover Todas", systemImage: "xmark")
                                        }
                                    }
                                } label: {
                                    Label("Etiquetas", systemImage: "tag")
                                }
                                Divider()
                                Button(action: {
                                    fileManager.deleteItems(contextItems(for: item))
                                }) {
                                    Label("Mover para Lixeira", systemImage: "trash")
                                }
                                Button(role: .destructive, action: {
                                    itemsToDelete = contextItems(for: item)
                                }) {
                                    Label("Excluir Permanentemente", systemImage: "xmark.bin")
                                }
                            }
                        }
                    }
                    .padding(16)

                    // Marquee Visual
                    if let start = selectionRectStart, let end = selectionRectEnd {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.3))
                            .stroke(Color.accentColor, lineWidth: 1)
                            .frame(
                                width: abs(end.x - start.x),
                                height: abs(end.y - start.y)
                            )
                            .position(
                                x: (start.x + end.x) / 2,
                                y: (start.y + end.y) / 2
                            )
                    }
                }
            }
            .onChange(of: geo.size.width) { _, newWidth in
                gridWidth = newWidth
            }
            .onAppear {
                gridWidth = geo.size.width
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

            Button(action: { fileManager.pasteItems() }) {
                Label("Colar", systemImage: "doc.on.clipboard")
            }
            .disabled(clipboardService.clipboard == nil)

            Button(action: { fileManager.openInTerminal() }) {
                Label("Abrir no Terminal", systemImage: "terminal")
            }
        }
    }

    private func selectRange(to item: FileItem) {
        if let anchorId = selectionAnchorID ?? lastSelectedID,
           let anchorIndex = sortedFiles.firstIndex(where: { $0.id == anchorId }),
           let currentIndex = sortedFiles.firstIndex(where: { $0.id == item.id })
        {
            let columnsCount = max(1, Int((gridWidth - 16) / 116))
            let startRow = anchorIndex / columnsCount
            let startCol = anchorIndex % columnsCount
            let endRow = currentIndex / columnsCount
            let endCol = currentIndex % columnsCount

            let minRow = min(startRow, endRow)
            let maxRow = max(startRow, endRow)
            let minCol = min(startCol, endCol)
            let maxCol = max(startCol, endCol)

            var boxIDs: Set<UUID> = []
            for r in minRow ... maxRow {
                for c in minCol ... maxCol {
                    let idx = r * columnsCount + c
                    if idx >= 0, idx < sortedFiles.count {
                        boxIDs.insert(sortedFiles[idx].id)
                    }
                }
            }
            selectedFileIDs = boxIDs
        } else {
            selectedFileIDs = [item.id]
            selectionAnchorID = item.id
        }
        lastSelectedID = item.id
    }

    private func updateSelectionFromMarquee() {
        guard let start = selectionRectStart, let end = selectionRectEnd else { return }

        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)

        let columnsCount = max(1, Int((gridWidth - 16) / 116))
        let itemSize: CGFloat = 116 // Estimativa do tamanho do item incluindo padding/spacing

        var newSelection: Set<UUID> = []

        for (index, item) in sortedFiles.enumerated() {
            let row = index / columnsCount
            let col = index % columnsCount

            let itemX = CGFloat(col) * itemSize + 16
            let itemY = CGFloat(row) * itemSize + 16

            let itemRect = CGRect(x: itemX, y: itemY, width: 100, height: 100)
            let marqueeRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            if itemRect.intersects(marqueeRect) {
                newSelection.insert(item.id)
            }
        }

        selectedFileIDs = newSelection
    }

    private func contextItems(for item: FileItem) -> [FileItem] {
        if selectedFileIDs.contains(item.id) {
            return sortedFiles.filter { selectedFileIDs.contains($0.id) }
        }

        return [item]
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

struct ItemInfoSheet: View {
    let item: FileItem
    @Binding var isPresented: Bool

    @State private var totalSize: Int64?
    @State private var itemCount: Int?
    @State private var isCalculatingSize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                FileIconView(item: item, size: CGSize(width: 48, height: 48))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.isDirectory ? "Pasta" : fileTypeDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                InfoRow(label: "Local", value: item.url.deletingLastPathComponent().path)
                InfoRow(label: "Criado", value: formattedDate(item.creationDate))
                InfoRow(label: "Modificado", value: formattedDate(item.modificationDate))
                InfoRow(label: "Tamanho", value: sizeText)
                if let itemCount {
                    InfoRow(label: "Itens", value: "\(itemCount)")
                }
                InfoRow(label: "Caminho completo", value: item.url.path)
            }

            Divider()

            HStack {
                Spacer()
                Button("Fechar") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task(id: item.id) {
            await loadSizeDetails()
        }
    }

    private var fileTypeDescription: String {
        let ext = item.url.pathExtension
        if ext.isEmpty {
            return "Arquivo"
        }
        return "Arquivo \(ext.uppercased())"
    }

    private var sizeText: String {
        if isCalculatingSize {
            return "Calculando..."
        }
        if let totalSize {
            return formattedSize(totalSize)
        }
        return item.formattedSize
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: date)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func loadSizeDetails() async {
        if !item.isDirectory {
            totalSize = item.fileSize
            itemCount = nil
            return
        }

        isCalculatingSize = true
        let url = item.url

        let details = await Task.detached {
            var total: Int64 = 0
            var count = 0
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]

            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return (total, count)
            }

            for case let childURL as URL in enumerator {
                if Task.isCancelled {
                    return (total, count)
                }

                count += 1
                let values = try? childURL.resourceValues(forKeys: keys)
                total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            }

            return (total, count)
        }.value

        totalSize = details.0
        itemCount = details.1
        isCalculatingSize = false
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
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
        let supportedExtensions = ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "pdf", "mp4", "mov"]
        guard supportedExtensions.contains(ext) else { return }

        if ext == "svg", let nsImage = NSImage(contentsOf: item.url) {
            thumbnail = nsImage
            return
        }

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
            } else if ext == "svg", let nsImage = NSImage(contentsOf: item.url) {
                DispatchQueue.main.async {
                    self.thumbnail = nsImage
                }
            }
        }
    }
}

struct RenameSheet: View {
    let item: FileItem
    @Binding var fileName: String
    @Binding var isPresented: Bool
    let onRename: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Renomear")
                .font(.headline)

            TextField("Novo nome", text: $fileName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancelar") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Renomear") {
                    onRename()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fileName.isEmpty || fileName == item.name)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

#Preview {
    FileListView(fileManager: FileManagerService())
}
