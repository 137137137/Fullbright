//
//  MenuBarContentView.swift
//  Fullbright
//

import SwiftUI
import Sparkle

struct MenuBarContentView: View {
    @Bindable var viewModel: MenuBarViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // XDR Control
            if viewModel.isXDRSupported {
                HStack {
                    Text("XDR Mode")
                        .font(MenuBarStyle.bodyFont)
                    Spacer()
                    Toggle("XDR Mode", isOn: Binding(
                        get: { viewModel.isXDREnabled },
                        set: { newValue in
                            viewModel.setXDREnabled(newValue)
                        }
                    ))
                    .labelsHidden()
                    .controlSize(.mini)
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, MenuBarStyle.horizontalPadding)
                .padding(.vertical, MenuBarStyle.xdrRowVerticalPadding)

                // Brightness slider, inert while XDR itself is off.
                HStack(spacing: 8) {
                    Image(systemName: "sun.min.fill")
                        .font(MenuBarStyle.captionFont)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.xdrBrightness) },
                            set: { viewModel.setXDRBrightness(Float($0)) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)
                    .accessibilityLabel("XDR Brightness")
                    Image(systemName: "sun.max.fill")
                        .font(MenuBarStyle.captionFont)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, MenuBarStyle.horizontalPadding)
                .padding(.bottom, MenuBarStyle.xdrRowVerticalPadding)
            } else {
                Text("No XDR Display Detected")
                    .font(MenuBarStyle.bodyFont)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MenuBarStyle.horizontalPadding)
                    .padding(.vertical, MenuBarStyle.xdrRowVerticalPadding)
            }

            Divider()

            // Check for Updates
            CheckForUpdatesView(viewModel: viewModel.checkForUpdatesViewModel)

            Divider()

            // Settings button
            Button(action: {
                openSettings()
                viewModel.activateApp()
            }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings...")
                    Spacer()
                    Text("\u{2318},")
                        .font(MenuBarStyle.captionFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuBarRowStyle()
            .accessibilityLabel("Settings")

            #if DEBUG
            Divider()

            // Developer menu
            Menu("Developer") {
                Button("Open Sparkle Testing...") {
                    NSWorkspace.shared.open(AppURL.sparkleTesting)
                }
            }
            .menuBarRowStyle()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif

            Divider()

            Button("Quit Fullbright") {
                viewModel.quitApp()
            }
            .menuBarRowStyle()
        }
        .frame(width: MenuBarStyle.popoverWidth)
    }
}
