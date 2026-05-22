//
//  FileListView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import AppKit
import ImageIO
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
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("viewMode") private var viewMode: ViewMode = .list
    @AppStorage("useLargerFolderIcons") private var useLargerFolderIcons = false
    @AppStorage("sortFoldersFirst") private var sortFoldersFirst = false
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
    @State private var rotatingItem: FileItem?
    @State private var resizingItem: FileItem?
    @State private var previewURL: URL?
    @State private var selectionRectStart: CGPoint? = nil
    @State private var selectionRectEnd: CGPoint? = nil
    @State private var initialSelectionForDrag: Set<UUID> = []
    @State private var searchText = ""
    @State private var itemsToCompress: [FileItem] = []
    @State private var showingCompressSheet = false
    @State private var dropTargetItemID: UUID? = nil
    @FocusState private var isListFocused: Bool
    @FocusState private var isSearchFocused: Bool

    var sortedFiles: [FileItem] {
        let sorted = fileManager.files.sorted(using: sortOrder)
        return sortFoldersFirst ? sorted.sorted { $0.isDirectory && !$1.isDirectory } : sorted
    }

    private var itemCountText: String {
        let count = sortedFiles.count
        let text = count == 1 ? languageManager.local("item_count_singular") : languageManager.local("item_count_plural")
        return "\(count) \(text)"
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isAnySheetPresented: Bool {
        showingCreateFolder ||
            showingCreateFile ||
            editingItem != nil ||
            rotatingItem != nil ||
            resizingItem != nil ||
            showingCompressSheet
    }

    private var iconSize: CGFloat {
        useLargerFolderIcons ? 68 : 56
    }

    private var iconTextSize: CGFloat {
        useLargerFolderIcons ? 12 : 11
    }

    private var iconLocationTextSize: CGFloat {
        useLargerFolderIcons ? 10 : 9
    }

    private var iconGridMinimum: CGFloat {
        useLargerFolderIcons ? 118 : 100
    }

    private var iconGridSpacing: CGFloat {
        16
    }

    private var iconTextWidth: CGFloat {
        useLargerFolderIcons ? 118 : 100
    }

    private var iconColumnsCount: Int {
        let availableWidth = max(0, gridWidth - 32)
        return max(1, Int((availableWidth + iconGridSpacing) / (iconGridMinimum + iconGridSpacing)))
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
                    TextField(languageManager.local("search_placeholder"), text: $searchText)
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
                .help(languageManager.local("paste"))

                Button(action: { fileManager.showHiddenFiles.toggle() }) {
                    Image(systemName: fileManager.showHiddenFiles ? "eye" : "eye.slash")
                }
                .help(fileManager.showHiddenFiles ? languageManager.local("hide_hidden") : languageManager.local("show_hidden"))

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
                    Text("\(languageManager.local("search_results_in")) \(fileManager.currentDirectory.path)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(itemCountText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
            }

            if sortedFiles.isEmpty, isSearching, !fileManager.isProcessing {
                ContentUnavailableView(
                    languageManager.local("no_items_found"),
                    systemImage: "magnifyingglass",
                    description: Text(languageManager.local("try_searching_again"))
                )
            } else {
                if viewMode == .list {
                    listView
                } else {
                    iconView
                }
            }
        }
        .background(sheetManager)
        .quickLookPreview($previewURL)
        .background(
            Group {
                Button(action: {
                    let items = sortedFiles.filter { selectedFileIDs.contains($0.id) }
                    if !items.isEmpty { fileManager.copyItems(items) }
                }) { EmptyView() }.keyboardShortcut("c", modifiers: .command)

                Button(action: {
                    if !isSearchFocused, !isAnySheetPresented {
                        selectedFileIDs = Set(sortedFiles.map { $0.id })
                    }
                }) { EmptyView() }.keyboardShortcut("a", modifiers: .command)

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
        .onChange(of: selectedFileIDs) { _, newValue in
            fileManager.selectedURLs = sortedFiles.filter { newValue.contains($0.id) }.map(\.url)
        }
        .onChange(of: sortedFiles) { _, newValue in
            fileManager.selectedURLs = newValue.filter { selectedFileIDs.contains($0.id) }.map(\.url)
        }
        .onChange(of: fileManager.currentDirectory) {
            searchText = ""
        }
        .onKeyPress { keyPress in
            if isAnySheetPresented { return .ignored }

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
                let selectedItems = sortedFiles.filter { selectedFileIDs.contains($0.id) }
                if !selectedItems.isEmpty {
                    fileManager.openItems(selectedItems)
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

                let columnsCount = iconColumnsCount
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
            TableColumn(languageManager.local("name"), value: \.name) { item in
                listRowContent(for: item)
            }

            if isSearching {
                TableColumn("Local") { item in
                    Text(locationText(for: item))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.url.deletingLastPathComponent().path)
                        .opacity(item.isHidden ? 0.45 : 1.0)
                }
                .width(min: 180, ideal: 260)
            }

            TableColumn(languageManager.local("date"), value: \.modificationDate) { item in
                Text(item.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .opacity(item.isHidden ? 0.45 : 1.0)
            }
            .width(min: 120, max: 150)

            TableColumn(languageManager.local("size"), value: \.fileSize) { item in
                Text(item.formattedSize)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .opacity(item.isHidden ? 0.45 : 1.0)
            }
            .width(min: 80, max: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: UUID.self) { items in
            if let id = items.first, let item = fileManager.files.first(where: { $0.id == id }) {
                Button(action: {
                    fileManager.openItems(contextItems(for: item))
                }) {
                    Label(languageManager.local("open"), systemImage: "arrow.right.circle")
                }
                if items.count <= 1 {
                    Button(action: { editingItem = item }) {
                        Label(languageManager.local("rename"), systemImage: "pencil")
                    }
                    .disabled(item.isSystemProtected)
                }
                Button(action: {
                    let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                    showInfoPanels(for: items)
                }) {
                    Label(languageManager.local("get_info"), systemImage: "info.circle")
                }
                if item.isImage && items.count == 1 {
                    Divider()
                    Button(action: { rotatingItem = item }) {
                        Label(languageManager.local("rotate"), systemImage: "rotate.right")
                    }
                    Button(action: { resizingItem = item }) {
                        Label(languageManager.local("resize"), systemImage: "arrow.up.backward.and.arrow.down.forward")
                    }
                }
                if item.isDirectory && items.count == 1 {
                    Button(action: { fileManager.openInTerminal(url: item.url) }) {
                        Label(languageManager.local("open_terminal"), systemImage: "terminal")
                    }
                    if fileManager.isFavorite(item.url) {
                        Button(action: { fileManager.removeFromFavorites(item.url) }) {
                            Label(languageManager.local("remove_favorites"), systemImage: "star.slash")
                        }
                    } else {
                        Button(action: { fileManager.addToFavorites(item.url) }) {
                            Label(languageManager.local("add_favorites"), systemImage: "star")
                        }
                    }
                    Divider()
                }
                Button(action: {
                    let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                    fileManager.copyItems(items)
                }) {
                    Label(languageManager.local("copy"), systemImage: "doc.on.doc")
                }
                Button(action: {
                    let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                    fileManager.cutItems(items)
                }) {
                    Label(languageManager.local("cut"), systemImage: "scissors")
                }
                .disabled(contextItems(for: item).contains(where: \.isSystemProtected))
                Divider()
                Button(action: {
                    let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
                    itemsToCompress = items
                    showingCompressSheet = true
                }) {
                    Label(languageManager.local("compress"), systemImage: "archivebox")
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
                                Text(languageManager.local(tag.rawValue))
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
                            Label(languageManager.local("remove_all"), systemImage: "xmark")
                        }
                    }
                } label: {
                    Label(languageManager.local("tags"), systemImage: "tag")
                }
                Divider()
                Button(action: {
                    fileManager.deleteItems(contextItems(for: item))
                }) {
                    Label(languageManager.local("move_to_trash"), systemImage: "trash")
                }
                .disabled(contextItems(for: item).contains(where: \.isSystemProtected))
                Button(role: .destructive, action: {
                    itemsToDelete = contextItems(for: item)
                }) {
                    Label(languageManager.local("delete_permanently"), systemImage: "xmark.bin")
                }
                .disabled(contextItems(for: item).contains(where: \.isSystemProtected))
            }
        } primaryAction: { items in
            let selectedItems = fileManager.files.filter { items.contains($0.id) }
            fileManager.openItems(selectedItems)
        }
        .contextMenu {
            Button(action: { showingCreateFolder = true }) {
                Label(languageManager.local("new_folder"), systemImage: "folder.badge.plus")
            }
            Button(action: { showingCreateFile = true }) {
                Label(languageManager.local("new_file"), systemImage: "doc.badge.plus")
            }
            Divider()

            Button(action: { fileManager.pasteItems() }) {
                Label(languageManager.local("paste"), systemImage: "doc.on.clipboard")
            }
            .disabled(clipboardService.clipboard == nil)

            Button(action: { fileManager.openInTerminal() }) {
                Label(languageManager.local("open_terminal"), systemImage: "terminal")
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
                                        initialSelectionForDrag = selectedFileIDs
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
                        GridItem(.adaptive(minimum: iconGridMinimum), spacing: iconGridSpacing),
                    ], spacing: iconGridSpacing) {
                        ForEach(sortedFiles) { item in
                            iconItemView(for: item)
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
                Label(languageManager.local("new_folder"), systemImage: "folder.badge.plus")
            }
            Button(action: { showingCreateFile = true }) {
                Label(languageManager.local("new_file"), systemImage: "doc.badge.plus")
            }
            Divider()

            Button(action: { fileManager.pasteItems() }) {
                Label(languageManager.local("paste"), systemImage: "doc.on.clipboard")
            }
            .disabled(clipboardService.clipboard == nil)

            Button(action: { fileManager.openInTerminal() }) {
                Label(languageManager.local("open_terminal"), systemImage: "terminal")
            }
        }
    }

    // MARK: - Extracted Views (required to avoid Swift type-checker timeout)

    @ViewBuilder
    private func listRowContent(for item: FileItem) -> some View {
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
        .opacity(item.isHidden ? 0.45 : 1.0)
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .dropDestination(for: URL.self) { droppedURLs, _ in
            guard item.isDirectory else { return false }
            let urlsToMove = resolveDropURLs(droppedURLs)
                .filter { $0 != item.url }
            guard !urlsToMove.isEmpty else { return false }
            fileManager.moveItems(urlsToMove, to: item.url)
            return true
        } isTargeted: { _ in
        }
    }

    /// When dragging a single item that is part of a multi-selection,
    /// expand the drop to include all selected file URLs.
    private func resolveDropURLs(_ droppedURLs: [URL]) -> [URL] {
        if droppedURLs.count == 1, let droppedURL = droppedURLs.first,
           let draggedItem = sortedFiles.first(where: { $0.url == droppedURL }),
           selectedFileIDs.contains(draggedItem.id),
           selectedFileIDs.count > 1
        {
            return sortedFiles.filter { selectedFileIDs.contains($0.id) }.map(\.url)
        }
        return droppedURLs
    }

    @ViewBuilder
    private func iconItemContent(for item: FileItem) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                FileIconView(item: item, size: CGSize(width: iconSize, height: iconSize))
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
                .font(.system(size: iconTextSize))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: iconTextWidth)
            if isSearching {
                Text(locationText(for: item))
                    .font(.system(size: iconLocationTextSize))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .frame(maxWidth: iconTextWidth)
            }
        }
        .opacity(item.isHidden ? 0.45 : 1.0)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedFileIDs.contains(item.id) ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(dropTargetItemID == item.id ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    @ViewBuilder
    private func iconItemView(for item: FileItem) -> some View {
        iconItemContent(for: item)
            .onDrag {
                NSItemProvider(object: item.url as NSURL)
            }
            .dropDestination(for: URL.self) { droppedURLs, _ in
                guard item.isDirectory else { return false }
                let urlsToMove = resolveDropURLs(droppedURLs)
                    .filter { $0 != item.url }
                guard !urlsToMove.isEmpty else { return false }
                fileManager.moveItems(urlsToMove, to: item.url)
                return true
            } isTargeted: { isTargeted in
                dropTargetItemID = isTargeted ? item.id : nil
            }
            .onTapGesture(count: 2) {
                fileManager.openItems(contextItems(for: item))
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    let flags = NSApp.currentEvent?.modifierFlags ?? []
                    if flags.contains(.command) || flags.contains(.shift) {
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
                iconContextMenu(for: item)
            }
    }

    @ViewBuilder
    private func iconContextMenu(for item: FileItem) -> some View {
        Button(action: {
            fileManager.openItems(contextItems(for: item))
        }) {
            Label(languageManager.local("open"), systemImage: "arrow.right.circle")
        }
        if contextItems(for: item).count <= 1 {
            Button(action: { editingItem = item }) {
                Label(languageManager.local("rename"), systemImage: "pencil")
            }
            .disabled(item.isSystemProtected)
        }
        Button(action: {
            let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
            showInfoPanels(for: items)
        }) {
            Label(languageManager.local("get_info"), systemImage: "info.circle")
        }
        if item.isImage && contextItems(for: item).count == 1 {
            Divider()
            Button(action: { rotatingItem = item }) {
                Label(languageManager.local("rotate"), systemImage: "rotate.right")
            }
            Button(action: { resizingItem = item }) {
                Label(languageManager.local("resize"), systemImage: "arrow.up.backward.and.arrow.down.forward")
            }
        }
        if item.isDirectory && (!selectedFileIDs.contains(item.id) || selectedFileIDs.count == 1) {
            Button(action: { fileManager.openInTerminal(url: item.url) }) {
                Label(languageManager.local("open_terminal"), systemImage: "terminal")
            }
            if fileManager.isFavorite(item.url) {
                Button(action: { fileManager.removeFromFavorites(item.url) }) {
                    Label(languageManager.local("remove_favorites"), systemImage: "star.slash")
                }
            } else {
                Button(action: { fileManager.addToFavorites(item.url) }) {
                    Label(languageManager.local("add_favorites"), systemImage: "star")
                }
            }
            Divider()
        }
        Button(action: {
            let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
            fileManager.copyItems(items)
        }) {
            Label(languageManager.local("copy"), systemImage: "doc.on.doc")
        }
        Button(action: {
            let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
            fileManager.cutItems(items)
        }) {
            Label(languageManager.local("cut"), systemImage: "scissors")
        }
        .disabled(contextItems(for: item).contains(where: \.isSystemProtected))
        Divider()
        Button(action: {
            let items = selectedFileIDs.contains(item.id) ? sortedFiles.filter { selectedFileIDs.contains($0.id) } : [item]
            itemsToCompress = items
            showingCompressSheet = true
        }) {
            Label(languageManager.local("compress"), systemImage: "archivebox")
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
                        Text(languageManager.local(tag.rawValue))
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
                    Label(languageManager.local("remove_all"), systemImage: "xmark")
                }
            }
        } label: {
            Label(languageManager.local("tags"), systemImage: "tag")
        }
        Divider()
        Button(action: {
            fileManager.deleteItems(contextItems(for: item))
        }) {
            Label(languageManager.local("move_to_trash"), systemImage: "trash")
        }
        .disabled(contextItems(for: item).contains(where: \.isSystemProtected))
        Button(role: .destructive, action: {
            itemsToDelete = contextItems(for: item)
        }) {
            Label(languageManager.local("delete_permanently"), systemImage: "xmark.bin")
        }
        .disabled(contextItems(for: item).contains(where: \.isSystemProtected))
    }

    private func showInfoPanels(for items: [FileItem]) {
        for (index, item) in items.enumerated() {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = languageManager.local("get_info") + " - " + item.name

            let closeAction: () -> Void = { [weak panel] in
                panel?.close()
            }

            let view = ItemInfoSheet(item: item, onClose: closeAction)
            panel.contentView = NSHostingView(rootView: view)

            let offset = CGFloat(index * 20)
            if let window = NSApp.keyWindow {
                let point = CGPoint(x: window.frame.minX + 50 + offset, y: window.frame.maxY - 50 - offset)
                panel.setFrameTopLeftPoint(point)
            } else {
                panel.center()
            }

            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func updateSelectionFromMarquee() {
        guard let start = selectionRectStart, let end = selectionRectEnd else { return }

        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)

        let availableWidth = max(0, gridWidth - 32)
        let columnsCount = max(1, iconColumnsCount)
        let spacing = iconGridSpacing
        let actualColumnWidth = (availableWidth - CGFloat(columnsCount - 1) * spacing) / CGFloat(columnsCount)
        let estimatedRowHeight: CGFloat = 110 // Estimated height for icon + text

        var newSelection: Set<UUID> = []

        for (index, item) in sortedFiles.enumerated() {
            let row = index / columnsCount
            let col = index % columnsCount

            let cellCenterX = 16 + CGFloat(col) * (actualColumnWidth + spacing) + actualColumnWidth / 2
            let cellTopY = 16 + CGFloat(row) * (estimatedRowHeight + spacing)

            let hitboxWidth = iconTextWidth
            let itemRect = CGRect(x: cellCenterX - hitboxWidth / 2, y: cellTopY, width: hitboxWidth, height: estimatedRowHeight)
            let marqueeRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            if itemRect.intersects(marqueeRect) {
                newSelection.insert(item.id)
            }
        }

        if NSApp.currentEvent?.modifierFlags.contains(.command) == true || NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            selectedFileIDs = initialSelectionForDrag.union(newSelection)
        } else {
            selectedFileIDs = newSelection
        }
    }

    private func contextItems(for item: FileItem) -> [FileItem] {
        if selectedFileIDs.contains(item.id) {
            return sortedFiles.filter { selectedFileIDs.contains($0.id) }
        }

        return [item]
    }

    @ViewBuilder
    private var sheetManager: some View {
        Color.clear
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
            .sheet(item: $rotatingItem) { item in
                RotateImageSheet(
                    isPresented: Binding(
                        get: { rotatingItem != nil },
                        set: { if !$0 { rotatingItem = nil } }
                    ),
                    item: item,
                    onApply: {
                        fileManager.loadDirectory()
                    }
                )
            }
            .sheet(item: $resizingItem) { item in
                ResizeImageSheet(
                    isPresented: Binding(
                        get: { resizingItem != nil },
                        set: { if !$0 { resizingItem = nil } }
                    ),
                    item: item,
                    onApply: { fileManager.loadDirectory() }
                )
            }
            .sheet(isPresented: $showingCompressSheet) {
                CompressSheet(
                    isPresented: $showingCompressSheet,
                    items: itemsToCompress,
                    onCompress: { (name: String, format: CompressionFormat) in
                        fileManager.compressItems(itemsToCompress, to: name, format: format)
                    }
                )
            }
            .alert(languageManager.local("error"), isPresented: Binding<Bool>(
                get: { fileManager.errorMessage != nil },
                set: { if !$0 { fileManager.errorMessage = nil } }
            )) {
                Button(languageManager.local("ok"), role: .cancel) {}
            } message: {
                if let errorMessage = fileManager.errorMessage {
                    Text(errorMessage)
                }
            }
            .confirmationDialog(
                languageManager.local("confirm_delete"),
                isPresented: Binding(
                    get: { !itemsToDelete.isEmpty },
                    set: { if !$0 { itemsToDelete = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button(languageManager.local("delete"), role: .destructive) {
                    fileManager.permanentDeleteItems(itemsToDelete)
                    itemsToDelete = []
                }
                Button(languageManager.local("cancel"), role: .cancel) {
                    itemsToDelete = []
                }
            } message: {
                if itemsToDelete.count == 1, let item = itemsToDelete.first {
                    Text(String(format: languageManager.local("delete_warning_singular"), item.name))
                } else {
                    Text(String(format: languageManager.local("delete_warning_plural"), itemsToDelete.count))
                }
            }
    }
}

struct CreateFolderSheet: View {
    @Binding var isPresented: Bool
    @Binding var folderName: String
    let onCreate: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Text(languageManager.local("new_folder"))
                .font(.headline)

            TextField(languageManager.local("folder_name_placeholder"), text: $folderName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(languageManager.local("cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(languageManager.local("create")) {
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
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Text(languageManager.local("new_file"))
                .font(.headline)

            TextField(languageManager.local("file_name_placeholder"), text: $fileName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(languageManager.local("cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(languageManager.local("create")) {
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
    var onClose: (() -> Void)? = nil
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var totalSize: Int64?
    @State private var itemCount: Int?
    @State private var isCalculatingSize = false
    @State private var imageDimensions: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                FileIconView(item: item, size: CGSize(width: 48, height: 48))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.isDirectory ? languageManager.local("folder") : fileTypeDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                InfoRow(label: languageManager.local("location"), value: item.url.deletingLastPathComponent().path)
                InfoRow(label: languageManager.local("created"), value: formattedDate(item.creationDate))
                InfoRow(label: languageManager.local("modified"), value: formattedDate(item.modificationDate))
                InfoRow(label: languageManager.local("size"), value: sizeText)
                if let imageDimensions {
                    InfoRow(label: languageManager.local("dimensions"), value: imageDimensions)
                }
                if let itemCount {
                    let itemsKey = itemCount == 1 ? "item_count_singular" : "item_count_plural"
                    let itemsStr = languageManager.local(itemsKey)
                    InfoRow(label: languageManager.local("contents"), value: "\(formattedBytes(Int64(itemCount))) \(itemsStr)")
                }
                InfoRow(label: languageManager.local("full_path"), value: item.url.path)
            }

            Divider()

            HStack {
                Spacer()
                Button(languageManager.local("close")) {
                    onClose?()
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
            return languageManager.local("file")
        }
        return "\(languageManager.local("file")) \(ext.uppercased())"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: bytes)) ?? "\(bytes)"
    }

    private var sizeText: String {
        if isCalculatingSize {
            return languageManager.local("calculating")
        }
        if let totalSize {
            let formatted = formattedSize(totalSize)
            let bytes = formattedBytes(totalSize)
            return "\(formatted) (\(bytes) bytes)"
        }
        let formatted = item.formattedSize
        let bytes = formattedBytes(item.fileSize)
        return "\(formatted) (\(bytes) bytes)"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
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

            let ext = item.url.pathExtension.lowercased()
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "bmp", "tiff", "tif"]
            if imageExtensions.contains(ext), let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) {
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                    let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
                    let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
                    if width > 0 && height > 0 {
                        imageDimensions = "\(width) x \(height)"
                    }
                }
            }
            return
        }

        isCalculatingSize = true
        let url = item.url

        let details = await Task.detached {
            var total: Int64 = 0
            var count = 0
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]

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
                if let values = try? childURL.resourceValues(forKeys: keys) {
                    if values.isRegularFile == true {
                        total += Int64(values.fileSize ?? 0)
                    }
                }
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
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var baseName: String = ""
    @State private var extensionName: String = ""
    @State private var hasExtension: Bool = false
    @State private var isExtensionLocked: Bool = true

    enum Field {
        case baseName
        case extensionName
    }

    @FocusState private var focusedField: Field?

    private var isRenameDisabled: Bool {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty {
            return true
        }

        let currentCombined: String
        if hasExtension {
            let trimmedExt = extensionName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedExt.isEmpty {
                currentCombined = trimmedBase
            } else {
                currentCombined = "\(trimmedBase).\(trimmedExt)"
            }
        } else {
            currentCombined = trimmedBase
        }

        return currentCombined == item.name
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(languageManager.local("rename"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.local("name_label"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField(languageManager.local("new_name_placeholder"), text: $baseName)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .baseName)

                        Menu {
                            Button(languageManager.local("uppercase")) {
                                baseName = baseName.uppercased()
                            }
                            Button(languageManager.local("lowercase")) {
                                baseName = baseName.lowercased()
                            }
                            Button(languageManager.local("capitalize")) {
                                baseName = baseName.capitalized
                            }
                        } label: {
                            Image(systemName: "textformat.size")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                                .frame(width: 22, height: 22)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .help(languageManager.local("text_case_help"))
                    }
                }

                // Extension (if applicable)
                if hasExtension {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.local("extension_label"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(".")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.secondary)

                                TextField("", text: $extensionName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13, design: .monospaced))
                                    .disabled(isExtensionLocked)
                                    .focused($focusedField, equals: .extensionName)
                            }

                            Button(action: {
                                isExtensionLocked.toggle()
                                if !isExtensionLocked {
                                    focusedField = .extensionName
                                } else {
                                    focusedField = .baseName
                                }
                            }) {
                                Image(systemName: isExtensionLocked ? "lock.fill" : "lock.open.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                                    .frame(width: 24, height: 24)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(languageManager.local(isExtensionLocked ? "unlock_extension_help" : "lock_extension_help"))
                        }
                    }
                }
            }

            HStack {
                Button(languageManager.local("cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(languageManager.local("rename")) {
                    if hasExtension {
                        let finalExtension = extensionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if finalExtension.isEmpty {
                            fileName = baseName
                        } else {
                            fileName = "\(baseName).\(finalExtension)"
                        }
                    } else {
                        fileName = baseName
                    }
                    onRename()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRenameDisabled)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            initializeNames()
            focusedField = .baseName
        }
    }

    private func initializeNames() {
        let originalName = item.name
        if !item.isDirectory, let lastDotIndex = originalName.lastIndex(of: ".") {
            if lastDotIndex > originalName.startIndex {
                baseName = String(originalName[..<lastDotIndex])
                extensionName = String(originalName[originalName.index(after: lastDotIndex)...])
                hasExtension = true
                return
            }
        }
        baseName = originalName
        extensionName = ""
        hasExtension = false
    }
}

struct CompressSheet: View {
    @Binding var isPresented: Bool
    let items: [FileItem]
    let onCompress: (String, CompressionFormat) -> Void
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var archiveName: String = ""
    @State private var format: CompressionFormat = .zip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(languageManager.local("compress_items"))
                .font(.headline)

            TextField(languageManager.local("archive_name"), text: $archiveName)
                .textFieldStyle(.roundedBorder)

            Picker(languageManager.local("format"), selection: $format) {
                ForEach(CompressionFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button(languageManager.local("cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(languageManager.local("compress")) {
                    onCompress(archiveName, format)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(archiveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
        .onAppear {
            if items.count == 1, let first = items.first {
                archiveName = first.url.deletingPathExtension().lastPathComponent
            } else {
                archiveName = "Archive"
            }
        }
    }
}

#Preview {
    FileListView(fileManager: FileManagerService())
}
