//
//  XDRDirtyFlagStoreTests.swift
//  FullbrightTests
//
//  Uses an isolated UserDefaults suite so tests don't pollute the
//  developer's real defaults.
//

import Foundation
import Testing
@testable import Fullbright

@MainActor
@Suite("XDRDirtyFlagStore")
struct XDRDirtyFlagStoreTests {

    private func makeStore(key: String = "test.dirty.flag") -> (UserDefaultsXDRDirtyFlagStore, UserDefaults, String) {
        let suiteName = "fb-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsXDRDirtyFlagStore(defaults: defaults, key: key)
        return (store, defaults, suiteName)
    }

    @Test("isDirty defaults to false on a fresh store")
    func freshStore_isNotDirty() {
        let (store, _, _) = makeStore()
        #expect(store.isDirty == false)
    }

    @Test("setting isDirty true persists across reads")
    func setDirty_persists() {
        let (store, _, _) = makeStore()
        store.isDirty = true
        #expect(store.isDirty == true)
    }

    @Test("clearing isDirty returns it to false")
    func clearDirty_persists() {
        let (store, _, _) = makeStore()
        store.isDirty = true
        store.isDirty = false
        #expect(store.isDirty == false)
    }

    @Test("restoreIfNeeded is a no-op when the flag is false")
    func restoreIfNeeded_whenClean_isNoOp() {
        let (store, _, _) = makeStore()
        store.restoreIfNeeded()
        #expect(store.isDirty == false)
    }

    @Test("restoreIfNeeded clears the flag after restoration")
    func restoreIfNeeded_whenDirty_clears() {
        let (store, _, _) = makeStore()
        store.isDirty = true
        store.restoreIfNeeded()
        #expect(store.isDirty == false)
    }

    @Test("two stores with the same key on the same suite share state")
    func twoStores_sameSuite_shareState() {
        let suiteName = "fb-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let key = "shared.key"
        let writer = UserDefaultsXDRDirtyFlagStore(defaults: defaults, key: key)
        let reader = UserDefaultsXDRDirtyFlagStore(defaults: defaults, key: key)

        writer.isDirty = true
        #expect(reader.isDirty == true)
    }
}
