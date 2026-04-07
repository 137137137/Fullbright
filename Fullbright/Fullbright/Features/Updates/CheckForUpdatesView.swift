//
//  CheckForUpdatesView.swift
//  Fullbright
//

import SwiftUI
import Sparkle

struct CheckForUpdatesView: View {
    // Received pre-constructed from the parent. Storing an @Observable
    // value directly (rather than wrapping it in @State) avoids the
    // re-init hazard where `@State`'s first-value-wins semantics ignore
    // updater changes on subsequent renders.
    let viewModel: CheckForUpdatesViewModel

    init(viewModel: CheckForUpdatesViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Button(action: viewModel.checkForUpdates) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(MenuBarStyle.bodyFont)
                Text("Check for Updates...")
                    .font(MenuBarStyle.bodyFont)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canCheckForUpdates)
        .padding(.horizontal, MenuBarStyle.horizontalPadding)
        .padding(.vertical, MenuBarStyle.verticalPadding)
        .contentShape(Rectangle())
        .accessibilityLabel("Check for Updates")
    }
}
