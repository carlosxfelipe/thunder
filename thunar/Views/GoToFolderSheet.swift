//
//  GoToFolderSheet.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 22/05/26.
//

import SwiftUI

struct GoToFolderSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var fileManager: FileManagerService
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var pathText: String = ""
    @State private var errorMessage: String? = nil

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text(languageManager.local("go_to_folder"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                TextField("~/", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        navigateToPath()
                    }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }

            HStack {
                Button(languageManager.local("cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(languageManager.local("go_button")) {
                    navigateToPath()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    private func navigateToPath() {
        let trimmedPath = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let resolvedPath = (trimmedPath as NSString).expandingTildeInPath
        let resolvedURL = URL(fileURLWithPath: resolvedPath)

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir) {
            if isDir.boolValue {
                fileManager.navigateTo(resolvedURL)
                isPresented = false
            } else {
                errorMessage = languageManager.local("folder_not_found")
            }
        } else {
            errorMessage = languageManager.local("folder_not_found")
        }
    }
}
