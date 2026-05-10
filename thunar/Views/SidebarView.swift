//
//  SidebarView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import SwiftUI

enum SidebarSelection: Hashable {
    case place(SidebarItem)
    case volume(URL)
}

struct SidebarView: View {
    @ObservedObject var fileManager: FileManagerService
    @StateObject private var volumesService = VolumesService()
    @State private var selection: SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            Section("Locais") {
                ForEach(SidebarItem.allCases) { item in
                    SidebarRow(item: item)
                        .tag(SidebarSelection.place(item))
                }
            }

            if !volumesService.volumes.isEmpty {
                Section("Dispositivos") {
                    ForEach(volumesService.volumes) { volume in
                        Label(volume.name, systemImage: volume.icon)
                            .font(.system(size: 13))
                            .tag(SidebarSelection.volume(volume.url))
                            .help(volume.formattedCapacity ?? volume.url.path)
                            .contextMenu {
                                Button("Abrir") {
                                    fileManager.navigateTo(volume.url)
                                }
                                if volume.isEjectable || volume.isRemovable {
                                    Divider()
                                    Button("Ejetar") {
                                        _ = volumesService.eject(volume)
                                    }
                                }
                            }
                    }
                }
            }

            Section("Etiquetas") {
                ForEach(FinderTag.allCases) { tag in
                    Button(action: {
                        selection = nil
                        if fileManager.searchTag == tag {
                            fileManager.searchTag = nil
                        } else {
                            fileManager.searchTag = tag
                        }
                    }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 12, height: 12)
                            Text(tag.rawValue)
                                .font(.system(size: 13))
                            Spacer()
                            if fileManager.searchTag == tag {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: selection) {
            switch selection {
            case let .place(item):
                if fileManager.searchTag != nil { fileManager.searchTag = nil }
                fileManager.navigateTo(item.url)
            case let .volume(url):
                if fileManager.searchTag != nil { fileManager.searchTag = nil }
                fileManager.navigateTo(url)
            case .none:
                break
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
    }
}

struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        Label(item.rawValue, systemImage: item.icon)
            .font(.system(size: 13))
    }
}

#Preview {
    SidebarView(fileManager: FileManagerService())
}
