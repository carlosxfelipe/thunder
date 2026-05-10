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
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    BreadcrumbView(fileManager: fileManager)

                    FileListView(fileManager: fileManager)
                }

                if fileManager.statusMessage != nil || fileManager.isProcessing {
                    statusBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: fileManager.statusMessage)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("Thunar")
        .frame(minWidth: 800, minHeight: 600)
    }

    @ViewBuilder
    var statusBar: some View {
        HStack(spacing: 8) {
            if fileManager.isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
            }
            if let message = fileManager.statusMessage {
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
