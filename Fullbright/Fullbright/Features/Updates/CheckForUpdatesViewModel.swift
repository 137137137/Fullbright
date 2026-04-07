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
    @ObservationIgnored
    private var observation: NSKeyValueObservation?
    /// Most recent KVO→MainActor bridge task, retained so repeated KVO
    /// callbacks cancel their predecessor rather than piling up unstructured
    /// tasks on the global executor.
    @ObservationIgnored
    private var bridgeTask: Task<Void, Never>?

    init(updater: SPUUpdater) {
        self.updater = updater
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            // KVO fires on an arbitrary thread. Hop to the main actor,
            // cancelling any prior in-flight bridge task first.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.bridgeTask?.cancel()
                self.bridgeTask = Task { @MainActor [weak self] in
                    self?.canCheckForUpdates = change.newValue ?? false
                }
            }
        }
    }

    deinit {
        // NSKeyValueObservation invalidates itself on deinit; this is explicit
        // for clarity. The bridgeTask is naturally cancelled when `self` is
        // released because all its captures are `weak`.
        observation?.invalidate()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
