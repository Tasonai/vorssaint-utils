// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A spring-loaded quick-stash drop target in Dynamic Island for files dragged to the screen top.
struct NotchShelfDropTargetView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var shelf = ShelfService.shared
    @ObservedObject private var l10n = L10n.shared

    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    var body: some View {
        HStack(spacing: 12) {
            if service.mascotOn {
                NotchMascotView(look: NotchMascotSupport.look(), size: 24, followsDrag: true)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.95))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(text.dropHint)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(text.files)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    if shelf.visibleItems.count > 0 {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("\(shelf.visibleItems.count)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.blue.opacity(0.9))
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                )
                .allowsHitTesting(false)
        }
    }
}
