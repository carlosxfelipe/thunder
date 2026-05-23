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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(languageManager.local("about_thunder")) {
                    showAboutPanel()
                }
            }
            CommandMenu(languageManager.local("go")) {
                Button(languageManager.local("go_to_folder")) {
                    NotificationCenter.default.post(name: .showGoToFolderDialog, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
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

        credits.append(NSAttributedString(string: "\(languageManager.local("by")) Carlos Felipe Araújo\n", attributes: bodyAttrs))
        credits.append(NSAttributedString(string: "github.com/carlosxfelipe\n\n", attributes: linkAttrs))

        credits.append(NSAttributedString(
            string: languageManager.local("app_description"),
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

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["isMCPEnabled": true, "mcpPort": 8888])
        let isEnabled = defaults.bool(forKey: "isMCPEnabled")
        let port = defaults.integer(forKey: "mcpPort")
        ThunderMCPManager.shared.updateState(enabled: isEnabled, port: port)
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let languageManager = LanguageManager.shared

        let goToFolderItem = NSMenuItem(
            title: languageManager.local("go_to_folder"),
            action: #selector(dockGoToFolder),
            keyEquivalent: ""
        )
        goToFolderItem.target = self
        menu.addItem(goToFolderItem)

        return menu
    }

    @objc func dockGoToFolder() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .showGoToFolderDialog, object: nil)
    }
}

extension Notification.Name {
    static let showGoToFolderDialog = Notification.Name("showGoToFolderDialog")
}
