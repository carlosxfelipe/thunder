//
//  ThunderTests.swift
//  ThunderTests
//
//  Created by Carlos Felipe Araújo on 23/05/26.
//

import AppKit
import Foundation
import Testing
@testable import Thunder

@MainActor
@Suite(.serialized)
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

    @Test("Test All MCP Server Tools")
    func allMCPTools() async throws {
        let tabManager = TabManagerService()
        // Wait for it to initialize, then navigate to sandboxed tempDirectory
        try await Task.sleep(nanoseconds: 50_000_000)
        tabManager.activeFileManager?.navigateTo(tempDirectory)
        try await Task.sleep(nanoseconds: 100_000_000)

        ThunderMCPManager.shared.activeTabManager = tabManager

        // 1. Test getActiveTabPath
        let activePath = ThunderMCPManager.shared.getActiveTabPath()
        #expect(activePath != nil, "getActiveTabPath should return active path.")

        // 2. Test createFile & createFolder
        let folderName = "mcp_folder"
        let file1Name = "mcp_file1.txt"
        let file2Name = "mcp_file2.txt"

        let createdFolder = ThunderMCPManager.shared.createFolder(name: folderName)
        let createdFile1 = ThunderMCPManager.shared.createFile(name: file1Name)
        let createdFile2 = ThunderMCPManager.shared.createFile(name: file2Name)

        #expect(createdFolder == true)
        #expect(createdFile1 == true)
        #expect(createdFile2 == true)

        let folderURL = tempDirectory.appendingPathComponent(folderName)
        let file1URL = tempDirectory.appendingPathComponent(file1Name)
        let file2URL = tempDirectory.appendingPathComponent(file2Name)

        #expect(FileManager.default.fileExists(atPath: folderURL.path))
        #expect(FileManager.default.fileExists(atPath: file1URL.path))
        #expect(FileManager.default.fileExists(atPath: file2URL.path))

        // 3. Test listDirectoryContents
        let contents = ThunderMCPManager.shared.listDirectoryContents(path: tempDirectory.path)
        #expect(contents != nil)
        #expect(contents?.count ?? 0 >= 3)

        // 4. Test getFileMetadata
        let metadata = ThunderMCPManager.shared.getFileMetadata(path: file1URL.path)
        #expect(metadata != nil)
        #expect(metadata?["name"] as? String == file1Name)
        #expect(metadata?["isDirectory"] as? Bool == false)

        // 5. Test renameItem
        let renamedName = "mcp_file1_renamed.txt"
        let renamedURL = tempDirectory.appendingPathComponent(renamedName)
        let renameSuccess = ThunderMCPManager.shared.renameItem(path: file1URL.path, newName: renamedName)
        #expect(renameSuccess == true)
        #expect(!FileManager.default.fileExists(atPath: file1URL.path))
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))

        // 6. Test openInThunder
        let openSuccess = ThunderMCPManager.shared.openInThunder(path: folderURL.path)
        #expect(openSuccess == true)

        // 7. Test getSelectedFiles (mock selection)
        tabManager.activeFileManager?.selectedURLs = [file2URL]
        let selected = ThunderMCPManager.shared.getSelectedFiles()
        #expect(selected.contains(file2URL.path))

        // 8. Test compressItems & decompressItem
        let zipName = "mcp_file2.txt.zip"
        let zipURL = tempDirectory.appendingPathComponent(zipName)
        let compressSuccess = ThunderMCPManager.shared.compressItems(paths: [file2URL.path], format: "zip")
        #expect(compressSuccess == true)

        // Give compression task a moment to finish on system process
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(FileManager.default.fileExists(atPath: zipURL.path))

        // Decompress ZIP using decompressItem
        let decompressSuccess = ThunderMCPManager.shared.decompressItem(path: zipURL.path)
        #expect(decompressSuccess == true)
        try await Task.sleep(nanoseconds: 500_000_000)

        // 9. Test rotateImage & resizeImage with real 1x1 image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        let cgImage = context?.makeImage()
        let imageURL = tempDirectory.appendingPathComponent("test_image.png")

        if let cgImage = cgImage {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let pngData = rep.representation(using: .png, properties: [:])
            try? pngData?.write(to: imageURL)
        }

        #expect(FileManager.default.fileExists(atPath: imageURL.path))

        // Rotate image 90 degrees
        let rotatedPath = ThunderMCPManager.shared.rotateImage(path: imageURL.path, degrees: 90, saveAsCopy: true)
        #expect(rotatedPath != nil)
        #expect(FileManager.default.fileExists(atPath: rotatedPath!))

        // Resize image to 2x2 pixels
        let resizedPath = ThunderMCPManager.shared.resizeImage(path: imageURL.path, width: 2, height: 2, unit: "pixels", maintainAspectRatio: false, saveAsCopy: true)
        #expect(resizedPath != nil)
        #expect(FileManager.default.fileExists(atPath: resizedPath!))

        // 10. Test moveFiles (move renamed file into folder)
        let targetFileInFolder = folderURL.appendingPathComponent(renamedName)
        let moveSuccess = ThunderMCPManager.shared.moveFiles(sourcePaths: [renamedURL.path], targetDir: folderURL.path)
        #expect(moveSuccess == true)
        #expect(!FileManager.default.fileExists(atPath: renamedURL.path))
        #expect(FileManager.default.fileExists(atPath: targetFileInFolder.path))

        // 11. Test trashItems (move test_image.png to Trash safely)
        let trashSuccess = ThunderMCPManager.shared.trashItems(paths: [imageURL.path])
        #expect(trashSuccess == true)
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test("Test file execution permission toggling")
    func testToggleExecutionPermission() {
        let fileName = "test_script_toggle.sh"
        service.createFile(name: fileName)

        let fileURL = tempDirectory.appendingPathComponent(fileName)
        let item = FileItem(url: fileURL)

        // 1. Initial state (should not be executable by default)
        #expect(item.isScript == true, "Should be recognized as a script.")
        #expect(item.isExecutable == false, "Should not be executable initially.")

        // 2. Toggle to make it executable (+x)
        service.toggleExecutionPermission(for: item)
        #expect(service.errorMessage == nil)

        let updatedItem = FileItem(url: fileURL)
        #expect(updatedItem.isExecutable == true, "Should now be executable.")

        // 3. Toggle to remove execution permission (-x)
        service.toggleExecutionPermission(for: updatedItem)
        #expect(service.errorMessage == nil)

        let revertedItem = FileItem(url: fileURL)
        #expect(revertedItem.isExecutable == false, "Should no longer be executable.")
    }
}
