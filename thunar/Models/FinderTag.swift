//
//  FinderTag.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 10/05/26.
//

import SwiftUI

enum FinderTag: String, CaseIterable, Identifiable, Hashable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return Color(red: 1.0, green: 0.23, blue: 0.19)
        case .orange: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .green: return Color(red: 0.26, green: 0.85, blue: 0.32)
        case .blue: return Color(red: 0.25, green: 0.51, blue: 1.0)
        case .purple: return Color(red: 0.69, green: 0.32, blue: 0.87)
        case .gray: return Color(red: 0.56, green: 0.56, blue: 0.58)
        }
    }

    /// The macOS Finder tag index used in the `_kMDItemUserTags` plist format.
    /// Format is "TagName\n<index>" where index encodes the color.
    var finderColorIndex: Int {
        switch self {
        case .gray: return 1
        case .green: return 2
        case .purple: return 3
        case .blue: return 4
        case .yellow: return 5
        case .red: return 6
        case .orange: return 7
        }
    }

    /// Create a FinderTag from a macOS Finder color index.
    static func fromFinderColorIndex(_ index: Int) -> FinderTag? {
        switch index {
        case 1: return .gray
        case 2: return .green
        case 3: return .purple
        case 4: return .blue
        case 5: return .yellow
        case 6: return .red
        case 7: return .orange
        default: return nil
        }
    }

    /// The localized name used by macOS Finder in Portuguese.
    nonisolated var localizedPortugueseName: String {
        switch self {
        case .red: return "Vermelho"
        case .orange: return "Laranja"
        case .yellow: return "Amarelo"
        case .green: return "Verde"
        case .blue: return "Azul"
        case .purple: return "Roxo"
        case .gray: return "Cinza"
        }
    }

    /// Read tags from a file URL using the macOS extended attribute.
    static func tagsForURL(_ url: URL) -> [FinderTag] {
        guard let resourceValues = try? url.resourceValues(forKeys: [.tagNamesKey]),
              let tagNames = resourceValues.tagNames
        else {
            return []
        }

        return tagNames.compactMap { name in
            // Match by English key (red) OR Portuguese name (Vermelho)
            FinderTag.allCases.first { $0.rawValue == name || $0.localizedPortugueseName == name }
        }
    }

    /// Set tags on a file URL using the standard macOS API.
    static func setTags(_ tags: [FinderTag], on url: URL) throws {
        var resourceValues = URLResourceValues()
        // Always write the Portuguese name for compatibility with standard macOS Finder tags in PT-BR
        resourceValues.tagNames = tags.map { $0.localizedPortugueseName }
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
}
