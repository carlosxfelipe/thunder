//
//  ContentView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var fileManager = FileManagerService()

    var body: some View {
        NavigationSplitView {
            SidebarView(fileManager: fileManager)
        } detail: {
            VStack(spacing: 0) {
                BreadcrumbView(fileManager: fileManager)

                FileListView(fileManager: fileManager)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("Thunar")
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
