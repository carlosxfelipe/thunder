//
//  SettingsView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 14/05/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("hiddenSidebarItems") private var hiddenSidebarItems: String = ""
    @AppStorage("showVolumes") private var showVolumes: Bool = true
    @AppStorage("showTags") private var showTags: Bool = true
    @AppStorage("showFavorites") private var showFavorites: Bool = true

    @StateObject private var languageManager = LanguageManager.shared

    private var hiddenItemsSet: Set<String> {
        Set(hiddenSidebarItems.split(separator: ",").map(String.init))
    }

    private func isVisible(_ item: SidebarItem) -> Bool {
        !hiddenItemsSet.contains(item.id)
    }

    private func toggleVisibility(_ item: SidebarItem) {
        var set = hiddenItemsSet
        if set.contains(item.id) {
            set.remove(item.id)
        } else {
            set.insert(item.id)
        }
        hiddenSidebarItems = set.joined(separator: ",")
    }

    var body: some View {
        TabView {
            Form {
                Section {
                    Picker(selection: $languageManager.currentLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    } label: {
                        Text(languageManager.local("language"))
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text(languageManager.local("general"))
                        .font(.body)
                        .padding(.bottom, 8)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(languageManager.local("general"), systemImage: "gearshape")
            }
            .frame(width: 450, height: 200)

            Form {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Toggle(isOn: Binding(
                            get: { isVisible(item) },
                            set: { _ in toggleVisibility(item) }
                        )) {
                            Label(languageManager.local(item.rawValue), systemImage: item.icon)
                        }
                    }
                } header: {
                    Text(languageManager.local("show_items_sidebar"))
                        .font(.body)
                        .padding(.bottom, 8)
                }

                Section {
                    Toggle(languageManager.local("favorites"), isOn: $showFavorites)
                    Toggle(languageManager.local("devices"), isOn: $showVolumes)
                    Toggle(languageManager.local("tags"), isOn: $showTags)
                } header: {
                    Text(languageManager.local("sections"))
                        .font(.body)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(languageManager.local("sidebar"), systemImage: "sidebar.left")
            }
            .frame(width: 450, height: 550)
        }
        .padding(20)
    }
}

#Preview {
    SettingsView()
}
