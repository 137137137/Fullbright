//
//  DisplayLifecycleObserver.swift
//  Fullbright
//
//  Bridges NSWorkspace sleep/wake and NSApplication screen-parameter
//  notifications into simple callbacks. Screen-parameter changes arrive
//  in bursts during display reconfiguration, so they are debounced.
//

import AppKit
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "DisplayLifecycle")

@MainActor
final class DisplayLifecycleObserver: DisplayLifecycleObserving {
    var onScreensSleep: (@MainActor () -> Void)?
    var onWake: (@MainActor () -> Void)?
    var onDisplayParametersChanged: (@MainActor () -> Void)?

    private let debounceInterval: Duration
    private var observers: [any NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?

    init(debounceInterval: Duration = .seconds(1)) {
        self.debounceInterval = debounceInterval
    }

    func start() {
        guard observers.isEmpty else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                logger.info("Screens did sleep")
                self?.onScreensSleep?()
            }
        })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                logger.info("Did wake from sleep")
                self?.onWake?()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.scheduleDebouncedParameterChange()
            }
        })
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func scheduleDebouncedParameterChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let interval = self?.debounceInterval else { return }
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self else { return }
            logger.info("Display parameters changed (debounced)")
            self.onDisplayParametersChanged?()
        }
    }
}
