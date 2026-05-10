//
//  TabBarView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 10/05/26.
//

import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabManager: TabManagerService

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabManager.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTabID,
                            canClose: tabManager.tabs.count > 1,
                            onSelect: { tabManager.selectTab(tab) },
                            onClose: { tabManager.closeTab(tab) },
                            onDuplicate: { tabManager.duplicateTab(tab) }
                        )
                    }
                }
                .padding(.leading, 4)
            }

            Spacer(minLength: 0)

            // New tab button
            Button(action: { tabManager.addTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("Nova Aba")
        }
        .frame(height: 32)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct TabItemView: View {
    let tab: TabItem
    let isActive: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void

    @State private var isHovering = false

    private var tabTitle: String {
        tab.fileManager.currentDirectory.lastPathComponent
    }

    private var tabIcon: String {
        let path = tab.fileManager.currentDirectory.path
        if path == FileManager.default.homeDirectoryForCurrentUser.path {
            return "house.fill"
        } else if path == "/" {
            return "internaldrive"
        } else {
            return "folder.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tabIcon)
                .font(.system(size: 10))
                .foregroundColor(isActive ? .accentColor : .secondary)

            Text(tabTitle)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .foregroundColor(isActive ? .primary : .secondary)

            if canClose && (isHovering || isActive) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                    ? Color(NSColor.controlBackgroundColor)
                    : (isHovering ? Color.primary.opacity(0.04) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button(action: onDuplicate) {
                Label("Duplicar Aba", systemImage: "plus.square.on.square")
            }

            if canClose {
                Divider()
                Button(action: onClose) {
                    Label("Fechar Aba", systemImage: "xmark")
                }
            }
        }
    }
}

#Preview {
    TabBarView(tabManager: TabManagerService())
        .frame(width: 600)
}
