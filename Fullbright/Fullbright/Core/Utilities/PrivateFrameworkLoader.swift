//
//  PrivateFrameworkLoader.swift
//  Fullbright
//
//  Private framework symbol loading via dlopen/dlsym.
//

import Foundation

enum PrivateFrameworkLoader {
    /// Load a framework handle (for cases where multiple symbols share one dlopen).
    static func loadFramework(_ frameworkPath: String) -> UnsafeMutableRawPointer? {
        dlopen(frameworkPath, RTLD_LAZY)
    }

    /// Load a symbol from an already-opened framework handle.
    static func symbol<T>(_ name: String, from handle: UnsafeMutableRawPointer, as type: T.Type) -> T? {
        guard let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}
