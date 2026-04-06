//
//  CheckForUpdatesView.swift
//  Fullbright
//

import SwiftUI
import Sparkle

struct CheckForUpdatesView: View {
    @State private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button(action: checkForUpdatesViewModel.checkForUpdates) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                Text("Check for Updates...")
                    .font(.system(size: 13))
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
        .padding(.horizontal, MenuBarStyle.horizontalPadding)
        .padding(.vertical, MenuBarStyle.verticalPadding)
        .contentShape(Rectangle())
        .accessibilityLabel("Check for Updates")
    }
}
