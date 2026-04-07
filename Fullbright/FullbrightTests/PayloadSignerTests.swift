//
//  PayloadSignerTests.swift
//  FullbrightTests
//

import Foundation
import CryptoKit
import Testing
@testable import Fullbright

@Suite("HMACPayloadSigner")
struct PayloadSignerTests {

    private func makeSigner() -> HMACPayloadSigner {
        HMACPayloadSigner(key: SymmetricKey(size: .bits256))
    }

    @Test("sign then verify returns true")
    func signThenVerify_returnsTrue() {
        let signer = makeSigner()
        let data = Data("hello world".utf8)
        let signature = signer.sign(data)
        #expect(signer.verify(data, signature: signature))
    }

    @Test("verify with wrong data returns false")
    func verifyWithWrongData_returnsFalse() {
        let signer = makeSigner()
        let data = Data("hello world".utf8)
        let signature = signer.sign(data)
        let wrongData = Data("goodbye world".utf8)
        #expect(!signer.verify(wrongData, signature: signature))
    }

    @Test("verify with wrong signature returns false")
    func verifyWithWrongSignature_returnsFalse() {
        let signer = makeSigner()
        let data = Data("hello world".utf8)
        let wrongSignature = Data(repeating: 0xAB, count: 32)
        #expect(!signer.verify(data, signature: wrongSignature))
    }

    @Test("verify with different key returns false")
    func verifyWithDifferentKey_returnsFalse() {
        let signer1 = makeSigner()
        let signer2 = makeSigner()
        let data = Data("hello world".utf8)
        let signature = signer1.sign(data)
        #expect(!signer2.verify(data, signature: signature))
    }
}
