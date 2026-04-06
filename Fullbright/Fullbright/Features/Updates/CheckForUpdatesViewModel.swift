//
//  CheckForUpdatesViewModel.swift
//  Fullbright
//

import Foundation
import Sparkle

@MainActor
@Observable
final class CheckForUpdatesViewModel {
    var canCheckForUpdates = false
    private let updater: SPUUpdater
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        self.updater = updater
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = change.newValue ?? false
            }
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
