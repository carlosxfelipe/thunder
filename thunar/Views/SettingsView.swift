//
//  SettingsView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 14/05/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("hiddenSidebarItems") private var hiddenSidebarItems: String = ""
    @AppStorage("showVolumes") private var showVolumes: Bool = true
    @AppStorage("showTags") private var showTags: Bool = true
    @AppStorage("showFavorites") private var showFavorites: Bool = true
    @AppStorage("useLargerFolderIcons") private var useLargerFolderIcons = false

    @ObservedObject private var languageManager = LanguageManager.shared

    private var hiddenItemsSet: Set<String> {
        Set(hiddenSidebarItems.split(separator: ",").map(String.init))
    }

    private func isVisible(_ item: SidebarItem) -> Bool {
        !hiddenItemsSet.contains(item.id)
    }

    private func toggleVisibility(_ item: SidebarItem) {
        var set = hiddenItemsSet
        if set.contains(item.id) {
            set.remove(item.id)
        } else {
            set.insert(item.id)
        }
        hiddenSidebarItems = set.joined(separator: ",")
    }

    private struct DiskInfo {
        let total: Int64
        let free: Int64
        var used: Int64 { total - free }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

        func formatted(_ bytes: Int64) -> String {
            let fmt = ByteCountFormatter()
            fmt.countStyle = .file
            fmt.allowedUnits = [.useGB, .useTB]
            return fmt.string(fromByteCount: bytes)
        }
    }

    private struct VolumeInfo: Identifiable {
        let id: String
        let name: String
        let info: DiskInfo
    }

    @State private var allDiskInfos: [VolumeInfo] = []

    private func refreshDiskInfos() {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) else {
            allDiskInfos = []
            return
        }
        var result: [VolumeInfo] = []
        for url in urls {
            if let values = try? url.resourceValues(forKeys: keys),
               let total = values.volumeTotalCapacity
            {
                let importantFree = values.volumeAvailableCapacityForImportantUsage ?? 0
                let standardFree = Int64(values.volumeAvailableCapacity ?? 0)
                let free = importantFree > 0 ? importantFree : standardFree
                let name = values.volumeName ?? url.lastPathComponent
                let info = DiskInfo(total: Int64(total), free: Int64(free))
                result.append(VolumeInfo(id: url.path, name: name, info: info))
            }
        }
        allDiskInfos = result
    }

    var body: some View {
        TabView {
            Form {
                Section {
                    Picker(selection: $languageManager.currentLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    } label: {
                        Text(languageManager.local("language"))
                    }
                    .pickerStyle(.menu)

                    Toggle(languageManager.local("larger_folder_icons"), isOn: $useLargerFolderIcons)
                } header: {
                    Text(languageManager.local("general"))
                        .font(.body)
                        .padding(.bottom, 8)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(languageManager.local("general"), systemImage: "gearshape")
            }
            .frame(width: 450, height: 240)

            Form {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Toggle(isOn: Binding(
                            get: { isVisible(item) },
                            set: { _ in toggleVisibility(item) }
                        )) {
                            Label(languageManager.local(item.rawValue), systemImage: item.icon)
                        }
                    }
                } header: {
                    Text(languageManager.local("show_items_sidebar"))
                        .font(.body)
                        .padding(.bottom, 8)
                }

                Section {
                    Toggle(languageManager.local("favorites"), isOn: $showFavorites)
                    Toggle(languageManager.local("devices"), isOn: $showVolumes)
                    Toggle(languageManager.local("tags"), isOn: $showTags)
                } header: {
                    Text(languageManager.local("sections"))
                        .font(.body)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(languageManager.local("sidebar"), systemImage: "sidebar.left")
            }
            .frame(width: 450, height: 550)

            Form {
                if allDiskInfos.isEmpty {
                    Text(languageManager.local("storage_unavailable"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(allDiskInfos) { volume in
                        Section {
                            LabeledContent(languageManager.local("storage_total")) {
                                Text(volume.info.formatted(volume.info.total))
                                    .foregroundColor(.secondary)
                            }
                            LabeledContent(languageManager.local("storage_used")) {
                                Text(volume.info.formatted(volume.info.used))
                                    .foregroundColor(.secondary)
                            }
                            LabeledContent(languageManager.local("storage_free")) {
                                Text(volume.info.formatted(volume.info.free))
                                    .foregroundColor(.secondary)
                            }
                        } header: {
                            Text(volume.name)
                                .font(.body)
                                .padding(.bottom, 8)
                        } footer: {
                            let barColor: Color = volume.info.usedFraction > 0.9 ? .red : volume.info.usedFraction > 0.75 ? .orange : .accentColor
                            VStack(alignment: .leading, spacing: 6) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(barColor)
                                            .frame(width: geo.size.width * volume.info.usedFraction, height: 6)
                                    }
                                }
                                .frame(height: 6)
                                HStack {
                                    Text(languageManager.local("storage_used"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(languageManager.local("storage_free"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(languageManager.local("storage"), systemImage: "internaldrive")
            }
            .frame(width: 450, height: 350)
            .onAppear {
                refreshDiskInfos()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
                refreshDiskInfos()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
                refreshDiskInfos()
            }
        }
        .padding(20)
    }
}

#Preview {
    SettingsView()
}
