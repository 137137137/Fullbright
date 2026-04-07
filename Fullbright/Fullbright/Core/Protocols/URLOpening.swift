//
//  URLOpening.swift
//  Fullbright
//
//  Abstraction over NSWorkspace.shared.open so ViewModels don't depend
//  on AppKit.
//

import Foundation

@MainActor
protocol URLOpening: Sendable {
    func open(_ url: URL)
}
