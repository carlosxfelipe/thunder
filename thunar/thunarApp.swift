//
//  thunarApp.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import AppKit
import SwiftUI

@main
struct thunarApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Sobre o \(AppConfig.appName)") {
                    showAboutPanel()
                }
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func showAboutPanel() {
        let credits = NSMutableAttributedString()

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor,
            .link: URL(string: "https://github.com/carlosxfelipe")!,
        ]

        credits.append(NSAttributedString(string: "Por Carlos Felipe Araújo\n", attributes: bodyAttrs))
        credits.append(NSAttributedString(string: "github.com/carlosxfelipe\n\n", attributes: linkAttrs))
        credits.append(NSAttributedString(
            string: AppConfig.appDescription,
            attributes: bodyAttrs
        ))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: AppConfig.appName,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): AppConfig.copyright,
        ])
    }
}
