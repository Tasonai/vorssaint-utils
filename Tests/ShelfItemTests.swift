// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum ShelfItemTests {
    static func run(_ suite: TestSuite) {
        let dummyIcon = NSImage()
        let fileURL = URL(fileURLWithPath: "/tmp/sample.txt")
        let linkURL = URL(string: "https://example.com")!

        let fileItem = ShelfItem(payload: .file(fileURL), title: "sample.txt", icon: dummyIcon, isImage: false)
        let imageItem = ShelfItem(payload: .file(fileURL), title: "sample.png", icon: dummyIcon, isImage: true)
        let textItem = ShelfItem(payload: .text("Hello world"), title: "Note", icon: dummyIcon, isImage: false)
        let linkItem = ShelfItem(payload: .link(linkURL), title: "Link", icon: dummyIcon, isImage: false)

        suite.expect(!fileItem.isBatch, "single file is not a batch")
        suite.expect(fileItem.holdsFile, "file payload holds a file")
        suite.expect(!textItem.holdsFile, "text payload does not hold a file")
        suite.expect(!linkItem.holdsFile, "link payload does not hold a file")
        suite.expect(fileItem.leafCount == 1, "single item leaf count is 1")

        let batchItem = ShelfItem(payload: .batch([fileItem, imageItem, textItem]), title: "Bundle", icon: dummyIcon, isImage: false)
        suite.expect(batchItem.isBatch, "batch payload is recognized as batch")
        suite.expect(batchItem.batchItems.count == 3, "batch extracts nested items")
        suite.expect(batchItem.holdsFile, "batch containing files reports holdsFile")
        suite.expect(batchItem.leafCount == 3, "batch counts all leaves")

        let nestedBatch = ShelfItem(payload: .batch([batchItem, linkItem]), title: "Outer", icon: dummyIcon, isImage: false)
        suite.expect(nestedBatch.leafCount == 4, "nested batch recursively counts all leaves")

        // Content equality vs ID equality
        let item1 = ShelfItem(id: fileItem.id, payload: .file(fileURL), title: "sample.txt", icon: dummyIcon, isImage: false)
        suite.expect(fileItem == item1, "same ID compares equal with ==")
        suite.expect(fileItem.hasSameContent(as: item1), "identical payload and icon have same content")

        let modifiedContent = ShelfItem(id: fileItem.id, payload: .file(fileURL), title: "renamed.txt", icon: dummyIcon, isImage: false)
        suite.expect(fileItem == modifiedContent, "same ID compares equal even with different title")
        suite.expect(!fileItem.hasSameContent(as: modifiedContent), "different title is recognized by hasSameContent")
    }
}
