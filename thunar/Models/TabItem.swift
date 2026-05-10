//
//  TabItem.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 10/05/26.
//

import Foundation

struct TabItem: Identifiable, Equatable {
    let id: UUID
    let fileManager: FileManagerService

    init(directory: URL? = nil) {
        id = UUID()
        fileManager = FileManagerService()
        if let directory = directory {
            fileManager.navigateTo(directory)
        }
    }

    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id
    }
}
