//
//  SidebarView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var fileManager: FileManagerService
    @State private var selectedItem: SidebarItem?

    var body: some View {
        List(selection: $selectedItem) {
            Section("Locais") {
                ForEach(SidebarItem.allCases) { item in
                    SidebarRow(item: item)
                        .tag(item)
                }
            }

            Section("Etiquetas") {
                ForEach(FinderTag.allCases) { tag in
                    Button(action: {
                        selectedItem = nil
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
        .onChange(of: selectedItem) {
            if let item = selectedItem {
                fileManager.searchTag = nil
                fileManager.navigateTo(item.url)
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
