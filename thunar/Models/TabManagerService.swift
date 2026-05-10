//
//  TabManagerService.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 10/05/26.
//

import Combine
import Foundation
import SwiftUI

@MainActor
class TabManagerService: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var activeTabID: UUID

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let initialTab = TabItem()
        tabs = [initialTab]
        activeTabID = initialTab.id
        observeTab(initialTab)
    }

    var activeTab: TabItem? {
        tabs.first { $0.id == activeTabID }
    }

    var activeFileManager: FileManagerService? {
        activeTab?.fileManager
    }

    func addTab(directory: URL? = nil) {
        let newTab = TabItem(directory: directory)
        tabs.append(newTab)
        activeTabID = newTab.id
        observeTab(newTab)
    }

    func closeTab(_ tab: TabItem) {
        guard tabs.count > 1 else { return }

        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)

            if activeTabID == tab.id {
                // Activate the nearest tab
                let newIndex = min(index, tabs.count - 1)
                activeTabID = tabs[newIndex].id
            }
        }
    }

    func selectTab(_ tab: TabItem) {
        activeTabID = tab.id
    }

    func duplicateTab(_ tab: TabItem) {
        let newTab = TabItem(directory: tab.fileManager.currentDirectory)
        if let index = tabs.firstIndex(of: tab) {
            tabs.insert(newTab, at: index + 1)
        } else {
            tabs.append(newTab)
        }
        activeTabID = newTab.id
        observeTab(newTab)
    }

    func selectNextTab() {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        activeTabID = tabs[nextIndex].id
    }

    func selectPreviousTab() {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let previousIndex = (currentIndex - 1 + tabs.count) % tabs.count
        activeTabID = tabs[previousIndex].id
    }

    /// Observe changes in a tab's FileManagerService to trigger UI updates
    private func observeTab(_ tab: TabItem) {
        tab.fileManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
