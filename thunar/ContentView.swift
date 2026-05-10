//
//  ContentView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var tabManager = TabManagerService()

    var body: some View {
        NavigationSplitView {
            SidebarView(fileManager: currentFileManager)
        } detail: {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    TabBarView(tabManager: tabManager)

                    BreadcrumbView(fileManager: currentFileManager)

                    FileListView(fileManager: currentFileManager)
                }

                if currentFileManager.statusMessage != nil || currentFileManager.isProcessing {
                    statusBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: currentFileManager.statusMessage)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle(windowTitle)
        .frame(minWidth: 800, minHeight: 600)
        .background(
            Group {
                // Tab shortcuts
                Button(action: { tabManager.addTab() }) { EmptyView() }
                    .keyboardShortcut("t", modifiers: .command)

                Button(action: { closeCurrentTab() }) { EmptyView() }
                    .keyboardShortcut("w", modifiers: .command)

                Button(action: { tabManager.selectNextTab() }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent.tab, modifiers: [.control])

                Button(action: { tabManager.selectPreviousTab() }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent.tab, modifiers: [.control, .shift])
            }
            .opacity(0)
        )
    }

    private var currentFileManager: FileManagerService {
        tabManager.activeFileManager ?? FileManagerService()
    }

    private var windowTitle: String {
        if let tag = currentFileManager.searchTag {
            return "Etiqueta: \(tag.rawValue)"
        }
        return currentFileManager.currentDirectory.lastPathComponent
    }

    private func closeCurrentTab() {
        if let tab = tabManager.activeTab, tabManager.tabs.count > 1 {
            tabManager.closeTab(tab)
        }
    }

    @ViewBuilder
    var statusBar: some View {
        HStack(spacing: 8) {
            if currentFileManager.isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
            }
            if let message = currentFileManager.statusMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.bottom, 16)
    }
}

#Preview {
    ContentView()
}
