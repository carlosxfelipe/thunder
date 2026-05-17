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
    case favorite(URL)
}

struct SidebarView: View {
    @ObservedObject var fileManager: FileManagerService
    @StateObject private var volumesService = VolumesService()
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var selection: SidebarSelection?

    @AppStorage("hiddenSidebarItems") private var hiddenSidebarItems: String = ""
    @AppStorage("showVolumes") private var showVolumes: Bool = true
    @AppStorage("showTags") private var showTags: Bool = true
    @AppStorage("showFavorites") private var showFavorites: Bool = true

    private var hiddenItemsSet: Set<String> {
        Set(hiddenSidebarItems.split(separator: ",").map(String.init))
    }

    private func isVisible(_ item: SidebarItem) -> Bool {
        !hiddenItemsSet.contains(item.id)
    }

    var body: some View {
        List(selection: $selection) {
            Section(languageManager.local("locations")) {
                ForEach(SidebarItem.allCases.filter(isVisible)) { item in
                    SidebarRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = .place(item)
                            fileManager.navigateTo(item.url)
                        }
                        .tag(SidebarSelection.place(item))
                }
            }

            if showFavorites && !fileManager.favorites.isEmpty {
                Section(languageManager.local("favorites")) {
                    ForEach(fileManager.favorites, id: \.self) { url in
                        FavoriteRow(url: url)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = .favorite(url)
                                fileManager.navigateTo(url)
                            }
                            .tag(SidebarSelection.favorite(url))
                            .contextMenu {
                                Button(languageManager.local("remove_favorites")) {
                                    fileManager.removeFromFavorites(url)
                                }
                            }
                    }
                }
            }

            if showVolumes && !volumesService.volumes.isEmpty {
                Section(languageManager.local("devices")) {
                    ForEach(volumesService.volumes) { volume in
                        VolumeRow(volume: volume, languageManager: languageManager) {
                            _ = volumesService.eject(volume)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = .volume(volume.url)
                            fileManager.navigateTo(volume.url)
                        }
                        .tag(SidebarSelection.volume(volume.url))
                        .help(volume.formattedCapacity(using: languageManager) ?? volume.url.path)
                        .contextMenu {
                            Button(languageManager.local("open")) {
                                fileManager.navigateTo(volume.url)
                            }
                            if volume.canEject {
                                Divider()
                                Button(languageManager.local("eject")) {
                                    _ = volumesService.eject(volume)
                                }
                            }
                        }
                    }
                }
            }

            if showTags {
                Section(languageManager.local("tags")) {
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
                                Text(languageManager.local(tag.rawValue))
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
        }
        .onChange(of: selection) {
            switch selection {
            case let .place(item):
                if fileManager.searchTag != nil { fileManager.searchTag = nil }
                fileManager.navigateTo(item.url)
            case let .volume(url):
                if fileManager.searchTag != nil { fileManager.searchTag = nil }
                fileManager.navigateTo(url)
            case let .favorite(url):
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
    @ObservedObject var languageManager = LanguageManager.shared

    var body: some View {
        Label(languageManager.local(item.rawValue), systemImage: item.icon)
            .font(.system(size: 13))
    }
}

struct FavoriteRow: View {
    let url: URL

    var body: some View {
        Label(url.lastPathComponent, systemImage: "folder.fill")
            .font(.system(size: 13))
    }
}

struct VolumeRow: View {
    let volume: MountedVolume
    let languageManager: LanguageManager
    let onEject: () -> Void

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(volume.name)
                Spacer(minLength: 0)
                if volume.canEject {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onEject()
                        }
                        .help("\(languageManager.local("eject")) \(volume.name)")
                }
            }
        } icon: {
            Image(systemName: volume.icon)
        }
        .font(.system(size: 13))
    }
}

#Preview {
    SidebarView(fileManager: FileManagerService())
}
