//
//  SidebarItem.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import Foundation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Início"
    case desktop = "Área de Trabalho"
    case documents = "Documentos"
    case downloads = "Downloads"
    case applications = "Aplicativos"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .desktop: return "desktopcomputer"
        case .documents: return "doc.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .applications: return "app.fill"
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
        case .downloads:
            return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        case .applications:
            return URL(fileURLWithPath: "/Applications")
        }
    }
}
