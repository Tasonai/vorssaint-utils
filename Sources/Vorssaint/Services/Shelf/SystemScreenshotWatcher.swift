// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Monitors the macOS system screenshot destination folder (e.g. ~/Desktop or
/// customized com.apple.screencapture location). When a new screenshot is saved
/// by macOS (⌘⇧3, ⌘⇧4, ⌘⇧5), it automatically shelfs the file and summons the
/// shelf with Force Touch feedback.
final class SystemScreenshotWatcher {
    static let shared = SystemScreenshotWatcher()

    private let queue = DispatchQueue(label: "com.vorssaint.utils.system-screenshot-watcher", qos: .userInitiated)
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var seenURLs = Set<URL>()
    private var isStarted = false

    private init() {}

    static var targetDirectory: URL {
        if let location = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !location.isEmpty {
            let expanded = (location as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    }

    func syncWithPreferences() {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.shelfCatchSystemScreenshots)
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() {
        guard !isStarted else { return }
        let dir = Self.targetDirectory

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        // Populate initial existing files so we don't treat them as new
        if let existing = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            seenURLs = Set(existing)
        } else {
            seenURLs.removeAll()
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.directoryChanged()
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        isStarted = true
        source.resume()
    }

    private func stopOnQueue() {
        guard isStarted else { return }
        isStarted = false
        fileDescriptor = -1
        source?.cancel()
        source = nil
    }

    private func directoryChanged() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.shelfCatchSystemScreenshots) else { return }
        let dir = Self.targetDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        var newScreenshots: [URL] = []

        for url in contents {
            if seenURLs.contains(url) { continue }
            seenURLs.insert(url)

            let name = url.lastPathComponent
            let isScreenshotName = name.hasPrefix("Снимок экрана")
                || name.hasPrefix("Screenshot")
                || name.hasPrefix("CleanShot")
                || name.hasPrefix("Screen Shot")

            guard isScreenshotName else { continue }

            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "heic"].contains(ext) else { continue }

            if let values = try? url.resourceValues(forKeys: [.creationDateKey]),
               let creation = values.creationDate,
               now.timeIntervalSince(creation) < 6.0 {
                newScreenshots.append(url)
            }
        }

        guard !newScreenshots.isEmpty else { return }

        DispatchQueue.main.async {
            ShelfService.shared.addFiles(newScreenshots)
            ShelfService.shared.summon()
            NotchFeedbackService.shared.performOpen()
            let msg = L10n.shared.language == .ru ? "Скриншот на полке" : "Screenshot shelved"
            QuickToolHUD.show(icon: "camera.viewfinder", message: msg)
        }
    }
}
