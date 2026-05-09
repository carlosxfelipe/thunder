//
//  FileListView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import AppKit
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
    @State private var selectedFileID: UUID?

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
                    Label("Lista", systemImage: "list.bullet")
                        .tag(ViewMode.list)
                    Label("Ícones", systemImage: "square.grid.2x2")
                        .tag(ViewMode.icons)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)

                Button(action: { fileManager.pasteItem() }) {
                    Image(systemName: "doc.on.clipboard")
                }
                .disabled(fileManager.clipboard == nil)
                .help("Colar")

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
    }

    var listView: some View {
        Table(fileManager.files, selection: $selectedFileID) {
            TableColumn("Nome") { item in
                HStack(spacing: 8) {
                    item.icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
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

            TableColumn("Data") { item in
                Text(item.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .width(min: 120, max: 150)

            TableColumn("Tamanho") { item in
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
                Button(action: { fileManager.deleteItem(item) }) {
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
                ForEach(fileManager.files) { item in
                    VStack(spacing: 8) {
                        item.icon
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .foregroundColor(.accentColor)
                        Text(item.name)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 100)
                    }
                    .padding(12)
                    .background(selectedFileID == item.id ? Color.accentColor.opacity(0.2) : Color.clear)
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
                            selectedFileID = item.id
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
                        Button(action: { fileManager.deleteItem(item) }) {
                            Label("Mover para Lixeira", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
        .contextMenu {
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

#Preview {
    FileListView(fileManager: FileManagerService())
}
