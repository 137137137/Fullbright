//
//  MenuBarStyle.swift
//  Fullbright
//
//  Style constants for menu bar popover content.
//

import SwiftUI

enum MenuBarStyle {
    static let bodyFont: Font = .system(size: 13)
    static let captionFont: Font = .system(size: 11)
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 6
    static let popoverWidth: CGFloat = 220
    static let xdrRowVerticalPadding: CGFloat = 8
}

struct MenuBarRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(MenuBarStyle.bodyFont)
            .padding(.horizontal, MenuBarStyle.horizontalPadding)
            .padding(.vertical, MenuBarStyle.verticalPadding)
    }
}

extension View {
    func menuBarRowStyle() -> some View {
        modifier(MenuBarRowStyle())
    }
}
