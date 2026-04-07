//
//  AppLifecycle.swift
//  Fullbright
//
//  Abstraction over app-termination so ViewModels don't depend on AppKit.
//

import Foundation

@MainActor
protocol AppLifecycle: Sendable {
    func terminate()
}
