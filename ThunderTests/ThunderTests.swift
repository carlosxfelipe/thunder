//
//  ThunderTests.swift
//  ThunderTests
//
//  Created by Carlos Felipe Araújo on 23/05/26.
//

import Foundation
import Testing
@testable import Thunder

@MainActor
final class ThunderTests {
    var service: FileManagerService
    var tempDirectory: URL

    init() {
        service = FileManagerService()

        // Setup a temporary directory for tests
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Point the service to our sandbox using synchronous state update to prevent race conditions
        service.currentDirectory = tempDirectory
        service.navigationHistory = [tempDirectory]
        service.historyIndex = 0
    }

    deinit {
        // Clean up the temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    @Test("Create a valid folder")
    func testCreateFolder() {
        let folderName = "TestFolder"
        service.createFolder(name: folderName)

        #expect(service.errorMessage == nil, "There should be no error message when creating a valid folder.")

        let folderURL = tempDirectory.appendingPathComponent(folderName)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir)

        #expect(exists && isDir.boolValue, "The folder should physically exist on disk and be a directory.")
    }

    @Test("Create a valid file")
    func testCreateFile() {
        let fileName = "testFile.txt"
        service.createFile(name: fileName)

        #expect(service.errorMessage == nil, "There should be no error message when creating a valid file.")

        let fileURL = tempDirectory.appendingPathComponent(fileName)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)

        #expect(exists && !isDir.boolValue, "The file should physically exist on disk and not be a directory.")
    }

    @Test("Duplicate folder creation error")
    func createDuplicateFolder() {
        let folderName = "DuplicatedFolder"

        // Create the first time
        service.createFolder(name: folderName)
        #expect(service.errorMessage == nil)

        // Try creating again
        service.createFolder(name: folderName)
        #expect(service.errorMessage != nil, "It should generate an error message when trying to create a folder with a duplicated name.")
    }

    @Test("Rename an item")
    func testRenameItem() {
        let oldName = "oldName.txt"
        let newName = "newName.txt"

        service.createFile(name: oldName)
        #expect(service.errorMessage == nil)

        // Directly instantiate the FileItem to bypass asynchronous UI load delays
        let itemURL = tempDirectory.appendingPathComponent(oldName)
        let itemToRename = FileItem(url: itemURL)

        service.renameItem(itemToRename, to: newName)
        #expect(service.errorMessage == nil)

        let oldExists = FileManager.default.fileExists(atPath: itemURL.path)
        let newExists = FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(newName).path)

        #expect(!oldExists, "The old file should no longer exist.")
        #expect(newExists, "The newly renamed file should exist.")
    }

    @Test("Permanent delete an item")
    func testPermanentDeleteItem() {
        let fileName = "toDelete.txt"
        service.createFile(name: fileName)
        #expect(service.errorMessage == nil)

        let itemURL = tempDirectory.appendingPathComponent(fileName)
        let itemToDelete = FileItem(url: itemURL)

        service.permanentDeleteItem(itemToDelete)
        #expect(service.errorMessage == nil)

        let exists = FileManager.default.fileExists(atPath: itemURL.path)
        #expect(!exists, "The file should be permanently deleted from disk.")
    }

    @Test("Smart Merge Directory - Keep Newer File")
    func smartMergeDirectory() throws {
        let sourceFolder = tempDirectory.appendingPathComponent("Source")
        let destFolder = tempDirectory.appendingPathComponent("Dest")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

        let fileName = "conflict.txt"
        let sourceFile = sourceFolder.appendingPathComponent(fileName)
        let destFile = destFolder.appendingPathComponent(fileName)

        try "newer".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "older".write(to: destFile, atomically: true, encoding: .utf8)

        // Make destFile older
        let oldDate = Date().addingTimeInterval(-1000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: destFile.path)

        // Call merge
        try service.mergeDirectory(source: sourceFolder, destination: destFolder, isCopy: false)

        // Verify destFile was replaced with newer content
        let content = try String(contentsOf: destFile, encoding: .utf8)
        #expect(content == "newer", "The older file should be replaced by the newer file during merge.")
    }

    @Test("Smart Merge Directory - Keep Destination if Newer")
    func smartMergeDirectoryKeepsNewerDest() throws {
        let sourceFolder = tempDirectory.appendingPathComponent("Source2")
        let destFolder = tempDirectory.appendingPathComponent("Dest2")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

        let fileName = "conflict.txt"
        let sourceFile = sourceFolder.appendingPathComponent(fileName)
        let destFile = destFolder.appendingPathComponent(fileName)

        try "older".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "newer".write(to: destFile, atomically: true, encoding: .utf8)

        // Make sourceFile older
        let oldDate = Date().addingTimeInterval(-1000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: sourceFile.path)

        // Call merge
        try service.mergeDirectory(source: sourceFolder, destination: destFolder, isCopy: false)

        // Verify destFile was NOT replaced (kept its newer content)
        let content = try String(contentsOf: destFile, encoding: .utf8)
        #expect(content == "newer", "The newer destination file should NOT be replaced by the older source file.")
    }

    @Test("Navigation History")
    func testNavigationHistory() async throws {
        // Wait for FileManagerService.init() async tasks to settle (it loads the home directory asynchronously)
        try await Task.sleep(nanoseconds: 100_000_000)

        let folderA = tempDirectory.appendingPathComponent("FolderA")
        let folderB = tempDirectory.appendingPathComponent("FolderB")

        // Create folders synchronously bypassing service.createFolder to prevent concurrent loadDirectory tasks
        try? FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

        // Setup initial navigation state for the test (overwriting whatever init() did)
        service.navigateTo(tempDirectory)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Initial state after init(): tempDirectory is in history
        #expect(service.currentDirectory == tempDirectory)
        let initialHistoryCount = service.navigationHistory.count

        // Navigate to FolderA
        service.navigateTo(folderA)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(service.currentDirectory == folderA)
        #expect(service.historyIndex == initialHistoryCount)

        // Navigate to FolderB
        service.navigateTo(folderB)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(service.currentDirectory == folderB)
        #expect(service.historyIndex == initialHistoryCount + 1)

        // Go back to FolderA
        service.navigateBack()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(service.currentDirectory == folderA)
        #expect(service.historyIndex == initialHistoryCount)

        // Go forward to FolderB
        service.navigateForward()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(service.currentDirectory == folderB)
        #expect(service.historyIndex == initialHistoryCount + 1)

        // Go to Parent (tempDirectory)
        service.navigateToParent()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(service.currentDirectory.standardizedFileURL == tempDirectory.standardizedFileURL)
    }
}
