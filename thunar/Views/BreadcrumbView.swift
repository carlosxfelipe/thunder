//
//  BreadcrumbView.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 09/05/26.
//

import SwiftUI

struct BreadcrumbView: View {
    @ObservedObject var fileManager: FileManagerService

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                breadcrumbComponents
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    var breadcrumbComponents: some View {
        let components = fileManager.currentDirectory.pathComponents

        return ForEach(0 ..< components.count, id: \.self) { index in
            let component = components[index]
            let isLast = index == components.count - 1

            if index == 0 {
                // Root or first component
                Button(action: {
                    fileManager.navigateTo(URL(fileURLWithPath: "/"))
                }) {
                    Image(systemName: "house.fill")
                        .foregroundColor(isLast ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                let currentPath = "/" + components[1 ... index].joined(separator: "/")

                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Button(action: {
                        fileManager.navigateTo(URL(fileURLWithPath: currentPath))
                    }) {
                        Text(component)
                            .font(.system(size: 13))
                            .foregroundColor(isLast ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    BreadcrumbView(fileManager: FileManagerService())
}
