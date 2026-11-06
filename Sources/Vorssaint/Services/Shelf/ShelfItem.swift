// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// A single item held on the floating shelf: a file, an image, a text snippet,
/// a URL link, or a batch (pile) containing multiple nested items.
struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    indirect enum Payload: Equatable {
        case file(URL)
        case text(String)
        case link(URL)
        case batch([ShelfItem])
    }
    let payload: Payload
    let title: String
    let icon: NSImage
    let isImage: Bool
    /// True once `icon` is a real decoded frame of the item's own
    /// content (an image thumbnail or a patched-in video frame), as
    /// opposed to a generic fallback icon. Purely a tile-sizing signal
    /// for ShelfTilesView: unlike `isImage`, it does not gate any
    /// decoding or kind-classification behavior.
    let hasContentThumbnail: Bool
    /// Finds a file payload again after a move or rename; nil for
    /// non-file payloads and for files whose bookmark could not be made.
    let bookmark: Data?

    init(id: UUID = UUID(), payload: Payload, title: String, icon: NSImage,
         isImage: Bool, hasContentThumbnail: Bool = false, bookmark: Data? = nil) {
        self.id = id
        self.payload = payload
        self.title = title
        self.icon = icon
        self.isImage = isImage
        self.hasContentThumbnail = hasContentThumbnail
        self.bookmark = bookmark
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }

    /// Unlike `==`, which is id-only for selection and lookup purposes,
    /// this compares what actually determines a tile's appearance.
    /// Needed because replaceItem swaps in a same-id item with a
    /// healed URL/title after a moved or renamed file's bookmark
    /// resolves - an id-only comparison would call that unchanged.
    func hasSameContent(as other: ShelfItem) -> Bool {
        guard id == other.id, title == other.title, isImage == other.isImage,
              hasContentThumbnail == other.hasContentThumbnail,
              icon === other.icon else { return false }
        switch (payload, other.payload) {
        case let (.file(lhs), .file(rhs)): return lhs == rhs
        case let (.text(lhs), .text(rhs)): return lhs == rhs
        case let (.link(lhs), .link(rhs)): return lhs == rhs
        case let (.batch(lhs), .batch(rhs)):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.hasSameContent(as: $1) }
        default: return false
        }
    }

    var isBatch: Bool {
        if case .batch = payload { return true }
        return false
    }

    var batchItems: [ShelfItem] {
        if case let .batch(items) = payload { return items }
        return []
    }

    var leafCount: Int {
        switch payload {
        case .file, .text, .link: return 1
        case let .batch(items): return items.reduce(0) { $0 + $1.leafCount }
        }
    }

    /// This item flattened into the kinds ShelfTooltipSupport's pile
    /// breakdown needs, recursing the same way leafCount does so a pile
    /// containing another pile still counts every real leaf.
    var tooltipLeafKinds: [ShelfTooltipLeafKind] {
        switch payload {
        case .file: return [isImage ? .image : .file]
        case .text: return [.note]
        case .link: return [.link]
        case let .batch(items): return items.flatMap { $0.tooltipLeafKinds }
        }
    }

    /// Whether this item, or anything nested in it, is a file. Recurses
    /// the way leafCount does but stops at the first one it finds.
    var holdsFile: Bool {
        switch payload {
        case .file: return true
        case .text, .link: return false
        case let .batch(items): return items.contains(where: \.holdsFile)
        }
    }
}
