//
//  ClipboardService.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 10/05/26.
//

import Combine
import Foundation
import SwiftUI

@MainActor
class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    enum ClipboardAction {
        case copy
        case cut
    }

    @Published var clipboard: (urls: [URL], action: ClipboardAction)? = nil

    private init() {}
}
