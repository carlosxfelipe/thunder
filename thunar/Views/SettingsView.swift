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
                    ForEach(SidebarItem.allCases) { item in
                        Toggle(isOn: Binding(
                            get: { isVisible(item) },
                            set: { _ in toggleVisibility(item) }
                        )) {
                            Label(item.rawValue, systemImage: item.icon)
                        }
                    }
                } header: {
                    Text("Mostrar estes itens na barra lateral:")
                        .font(.body)
                        .padding(.bottom, 8)
                }

                Section {
                    Toggle("Dispositivos", isOn: $showVolumes)
                    Toggle("Etiquetas", isOn: $showTags)
                } header: {
                    Text("Seções:")
                        .font(.body)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Barra Lateral", systemImage: "sidebar.left")
            }
            .frame(width: 450, height: 550)
        }
        .padding(20)
    }
}

#Preview {
    SettingsView()
}
