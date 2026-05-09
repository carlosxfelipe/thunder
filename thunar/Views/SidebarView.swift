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
        }
        .onChange(of: selectedItem) { newValue in
            if let item = newValue {
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
