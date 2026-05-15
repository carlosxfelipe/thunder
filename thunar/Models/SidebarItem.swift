//
//  SidebarItem.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import Foundation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case desktop
    case documents
    case movies
    case pictures
    case music
    case downloads
    case applications
    case trash

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .desktop: return "desktopcomputer"
        case .documents: return "doc.fill"
        case .movies: return "film"
        case .pictures: return "photo.fill"
        case .music: return "music.note"
        case .downloads: return "arrow.down.circle.fill"
        case .applications: return "app.fill"
        case .trash: return "trash.fill"
        }
    }

    var url: URL {
        let fileManager = FileManager.default

        switch self {
        case .home:
            return fileManager.homeDirectoryForCurrentUser
        case .desktop:
            return fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        case .documents:
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        case .movies:
            return fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        case .pictures:
            return fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        case .music:
            return fileManager.urls(for: .musicDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        case .downloads:
            return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        case .applications:
            return URL(fileURLWithPath: "/Applications")
        case .trash:
            return fileManager.urls(for: .trashDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        }
    }
}
