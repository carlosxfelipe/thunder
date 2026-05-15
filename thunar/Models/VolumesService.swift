//
//  VolumesService.swift
//  thunar
//
//  Created by Carlos Felipe Araújo on 10/05/26.
//

import AppKit
import Combine
import Foundation
import SwiftUI

struct MountedVolume: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isRemovable: Bool
    let isEjectable: Bool
    let isInternal: Bool
    let isLocal: Bool
    let totalCapacity: Int64?
    let availableCapacity: Int64?

    var icon: String {
        if isEjectable || isRemovable {
            return "externaldrive.fill"
        }
        if !isLocal {
            return "externaldrive.connected.to.line.below.fill"
        }
        return "internaldrive.fill"
    }

    /// Indicates if the volume can be ejected.
    /// External drives sometimes report isEjectable=false, but non-internal volumes
    /// should generally be ejectable (matching Finder behavior).
    var canEject: Bool {
        if isEjectable || isRemovable { return true }
        if !isInternal { return true }
        if !isLocal { return true }
        return false
    }

    func formattedCapacity(using languageManager: LanguageManager) -> String? {
        guard let total = totalCapacity else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        formatter.countStyle = .file
        if let available = availableCapacity {
            return String(format: languageManager.local("free_of"),
                          formatter.string(fromByteCount: available),
                          formatter.string(fromByteCount: total))
        }
        return formatter.string(fromByteCount: total)
    }
}

@MainActor
class VolumesService: ObservableObject {
    @Published var volumes: [MountedVolume] = []

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        registerNotifications()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func registerNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        let mount = center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main,
            using: handler
        )

        let unmount = center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main,
            using: handler
        )

        let rename = center.addObserver(
            forName: NSWorkspace.didRenameVolumeNotification,
            object: nil,
            queue: .main,
            using: handler
        )

        observers = [mount, unmount, rename]
    }

    func refresh() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsBrowsableKey,
            .volumeIsRootFileSystemKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            volumes = []
            return
        }

        let mapped: [MountedVolume] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }

            // Hide system/data volumes that the user shouldn't navigate
            if values.volumeIsRootFileSystem == true { return nil }
            if values.volumeIsBrowsable == false { return nil }
            if url.path.hasPrefix("/System/Volumes/") { return nil }

            let name = values.volumeName ?? url.lastPathComponent
            return MountedVolume(
                id: url,
                url: url,
                name: name,
                isRemovable: values.volumeIsRemovable ?? false,
                isEjectable: values.volumeIsEjectable ?? false,
                isInternal: values.volumeIsInternal ?? false,
                isLocal: values.volumeIsLocal ?? true,
                totalCapacity: (values.volumeTotalCapacity).map { Int64($0) },
                availableCapacity: (values.volumeAvailableCapacity).map { Int64($0) }
            )
        }

        volumes = mapped.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func eject(_ volume: MountedVolume) -> Bool {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            refresh()
            return true
        } catch {
            return false
        }
    }
}
