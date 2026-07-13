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
    /// A callback, not render state — exclude it from observation so
    /// reassigning it (e.g. in `show()`) doesn't invalidate the view.
    @ObservationIgnored var onChange: ((Float) -> Void)?
}
