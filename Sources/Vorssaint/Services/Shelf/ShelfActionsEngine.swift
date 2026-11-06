// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import PDFKit
import QuickLookUI
import UniformTypeIdentifiers
import Vision

/// Performs instant Dropover-style actions on files held in the Shelf:
/// ZIP compression, image format conversion (PNG/JPEG), EXIF/metadata stripping,
/// OCR text extraction, Quick Look previewing, and path copying.
enum ShelfActionsEngine {

    enum ImageTargetFormat: String, CaseIterable {
        case png = "PNG"
        case jpeg = "JPEG"

        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            }
        }

        var bitmapType: NSBitmapImageRep.FileType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            }
        }
    }

    /// Compresses given file URLs into a single .zip archive using macOS ditto,
    /// and optionally adds the resulting archive back onto the Shelf.
    static func compressToZip(urls: [URL], addToShelf: Bool = true, completion: ((URL?) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?(nil); return }

        DispatchQueue.global(qos: .userInitiated).async {
            let parentDir = urls[0].deletingLastPathComponent()
            let baseName = urls.count == 1
                ? urls[0].deletingPathExtension().lastPathComponent
                : "Archive"
            let targetURL = uniqueURL(in: parentDir, name: baseName, ext: "zip")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            var args = ["-c", "-k", "--sequesterRsrc", "--keepParent"]
            args.append(contentsOf: urls.map(\.path))
            args.append(targetURL.path)
            process.arguments = args

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0, FileManager.default.fileExists(atPath: targetURL.path) {
                    DispatchQueue.main.async {
                        NotchFeedbackService.shared.performSelection()
                        if addToShelf {
                            ShelfService.shared.addFiles([targetURL])
                        }
                        let msg = L10n.shared.language == .ru ? "Архив создан" : "ZIP archive created"
                        QuickToolHUD.show(icon: "archivebox", message: msg)
                        completion?(targetURL)
                    }
                    return
                }
            } catch {}

            DispatchQueue.main.async { completion?(nil) }
        }
    }

    /// Converts an image file to PNG or JPEG and adds the result to the Shelf.
    static func convertImage(url: URL, to format: ImageTargetFormat, addToShelf: Bool = true, completion: ((URL?) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let fileData = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: fileData),
                  let data = rep.representation(using: format.bitmapType, properties: [:]) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let baseName = url.deletingPathExtension().lastPathComponent
            let targetURL = uniqueURL(in: url.deletingLastPathComponent(), name: "\(baseName)-converted", ext: format.fileExtension)

            do {
                try data.write(to: targetURL)
                DispatchQueue.main.async {
                    NotchFeedbackService.shared.performSelection()
                    if addToShelf {
                        ShelfService.shared.addFiles([targetURL])
                    }
                    let msg = L10n.shared.language == .ru ? "Изображение сконвертировано" : "Image converted"
                    QuickToolHUD.show(icon: "photo", message: msg)
                    completion?(targetURL)
                }
            } catch {
                DispatchQueue.main.async { completion?(nil) }
            }
        }
    }

    /// Strips EXIF, GPS and camera metadata from an image for privacy and adds clean copy to the Shelf.
    static func stripMetadata(url: URL, addToShelf: Bool = true, completion: ((URL?) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let fileData = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: fileData) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let ext = url.pathExtension.lowercased()
            let fileType: NSBitmapImageRep.FileType = (ext == "png") ? .png : .jpeg
            guard let data = rep.representation(using: fileType, properties: [:]) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let baseName = url.deletingPathExtension().lastPathComponent
            let targetURL = uniqueURL(in: url.deletingLastPathComponent(), name: "\(baseName)-clean", ext: ext.isEmpty ? "jpg" : ext)

            do {
                try data.write(to: targetURL)
                DispatchQueue.main.async {
                    NotchFeedbackService.shared.performSelection()
                    if addToShelf {
                        ShelfService.shared.addFiles([targetURL])
                    }
                    let msg = L10n.shared.language == .ru ? "Метаданные (EXIF) удалены" : "EXIF metadata stripped"
                    QuickToolHUD.show(icon: "shield.lefthalf.filled", message: msg)
                    completion?(targetURL)
                }
            } catch {
                DispatchQueue.main.async { completion?(nil) }
            }
        }
    }

    /// Extracts text from an image using Vision OCR and copies it directly to the clipboard.
    static func extractTextOCR(from url: URL, completion: ((String?) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.declareVorssaintSource()
                        pb.setString(text, forType: .string)
                        NotchFeedbackService.shared.performSelection()
                        let msg = L10n.shared.language == .ru ? "Текст распознан и скопирован" : "Text recognized & copied"
                        QuickToolHUD.show(icon: "text.viewfinder", message: msg)
                        completion?(text)
                    } else {
                        let msg = L10n.shared.language == .ru ? "Текст не найден" : "No text found"
                        QuickToolHUD.show(icon: "text.viewfinder", message: msg)
                        completion?(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async { completion?(nil) }
            }
        }
    }

    /// Copies POSIX file paths to clipboard as newline-separated strings.
    static func copyFilePaths(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let text = urls.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareVorssaintSource()
        NSPasteboard.general.setString(text, forType: .string)
        NotchFeedbackService.shared.performSelection()
        let msg = L10n.shared.language == .ru ? "Пути скопированы" : "Paths copied"
        QuickToolHUD.show(icon: "doc.on.doc", message: msg)
    }

    /// Merges multiple images or PDF files into a single consolidated PDF document.
    static func mergeToPDF(urls: [URL], addToShelf: Bool = true, completion: ((URL?) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?(nil); return }

        DispatchQueue.global(qos: .userInitiated).async {
            let pdfDoc = PDFDocument()
            var pageIndex = 0

            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ext == "pdf", let sourceDoc = PDFDocument(url: url) {
                    for i in 0..<sourceDoc.pageCount {
                        if let page = sourceDoc.page(at: i) {
                            pdfDoc.insert(page, at: pageIndex)
                            pageIndex += 1
                        }
                    }
                } else if let image = NSImage(contentsOf: url),
                          let page = PDFPage(image: image) {
                    pdfDoc.insert(page, at: pageIndex)
                    pageIndex += 1
                }
            }

            guard pageIndex > 0 else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let parentDir = urls[0].deletingLastPathComponent()
            let targetURL = uniqueURL(in: parentDir, name: "Merged", ext: "pdf")
            if pdfDoc.write(to: targetURL) {
                DispatchQueue.main.async {
                    NotchFeedbackService.shared.performSelection()
                    if addToShelf {
                        ShelfService.shared.addFiles([targetURL])
                    }
                    let msg = L10n.shared.language == .ru ? "PDF объединён" : "PDF merged"
                    QuickToolHUD.show(icon: "doc.on.doc.fill", message: msg)
                    completion?(targetURL)
                }
            } else {
                DispatchQueue.main.async { completion?(nil) }
            }
        }
    }

    enum RenamePattern {
        case sequential(prefix: String)
        case slugify
    }

    /// Renames the given files according to the chosen pattern.
    static func batchRename(urls: [URL], pattern: RenamePattern, completion: (([URL]) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?([]) ; return }

        DispatchQueue.global(qos: .userInitiated).async {
            var newURLs: [URL] = []
            let fm = FileManager.default
            for (idx, url) in urls.enumerated() {
                let dir = url.deletingLastPathComponent()
                let ext = url.pathExtension
                let nameWithoutExt = url.deletingPathExtension().lastPathComponent

                let newName: String
                switch pattern {
                case .sequential(let prefix):
                    let p = prefix.isEmpty ? "File" : prefix
                    newName = "\(p)_\(idx + 1)"
                case .slugify:
                    let cleaned = nameWithoutExt
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "_")
                        .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).inverted)
                        .joined()
                    newName = cleaned.isEmpty ? "file_\(idx + 1)" : cleaned
                }

                let target = uniqueURL(in: dir, name: newName, ext: ext)
                if target.path != url.path {
                    do {
                        try fm.moveItem(at: url, to: target)
                        newURLs.append(target)
                    } catch {
                        newURLs.append(url)
                    }
                } else {
                    newURLs.append(url)
                }
            }

            DispatchQueue.main.async {
                NotchFeedbackService.shared.performSelection()
                let msg = L10n.shared.language == .ru ? "Файлы переименованы" : "Files renamed"
                QuickToolHUD.show(icon: "pencil.line", message: msg)
                completion?(newURLs)
            }
        }
    }

    private static func uniqueURL(in directory: URL, name: String, ext: String) -> URL {
        var candidate = directory.appendingPathComponent("\(name).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(index).\(ext)")
            index += 1
        }
        return candidate
    }
}

/// Coordinates Quick Look preview panels across the Shelf tiles.
final class ShelfQuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = ShelfQuickLookCoordinator()
    private var previewURLs: [URL] = []

    func toggle(urls: [URL]) {
        guard !urls.isEmpty else { return }
        previewURLs = urls
        if let panel = QLPreviewPanel.shared() {
            if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.dataSource = self
                panel.delegate = self
                panel.reloadData()
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < previewURLs.count else { return nil }
        return previewURLs[index] as NSURL
    }
}
