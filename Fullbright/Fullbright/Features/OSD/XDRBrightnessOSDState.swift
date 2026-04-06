//
//  XDRBrightnessOSDState.swift
//  Fullbright
//

import SwiftUI

@MainActor
@Observable
final class XDRBrightnessOSDState {
    var image = "sun.max.fill"
    var leadingIcon: String?
    var value: Float = 1.0
    var text = ""
    var leadingLabel = ""
    var locked = false
    var tip: String?
    var onChange: ((Float) -> Void)?
}
