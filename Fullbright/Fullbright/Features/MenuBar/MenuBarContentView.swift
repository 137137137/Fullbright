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
                        get: {
                            viewModel.canUseXDR ? viewModel.isXDREnabled : false
                        },
                        set: { newValue in
                            viewModel.setXDREnabled(newValue)
                        }
                    ))
                    .labelsHidden()
                    .controlSize(.mini)
                    .toggleStyle(.switch)
                    .disabled(!viewModel.canUseXDR)
                    .id(viewModel.canUseXDR)
                }
                .padding(.horizontal, MenuBarStyle.horizontalPadding)
                .padding(.vertical, 8)
            } else {
                Text("No XDR Display Detected")
                    .font(MenuBarStyle.bodyFont)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MenuBarStyle.horizontalPadding)
                    .padding(.vertical, 8)
            }

            Divider()

            // Check for Updates
            CheckForUpdatesView(viewModel: CheckForUpdatesViewModel(updater: viewModel.updaterController.updater))

            Divider()

            // Settings button
            Button(action: { openSettings() }) {
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
            .buttonStyle(.plain)
            .font(MenuBarStyle.bodyFont)
            .padding(.horizontal, MenuBarStyle.horizontalPadding)
            .padding(.vertical, MenuBarStyle.verticalPadding)
            .accessibilityLabel("Settings")

            #if DEBUG
            Divider()

            // Developer menu
            Menu("Developer") {
                Button("Open Sparkle Testing...") {
                    if let url = URL(string: "fullbright://sparkle-testing") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Set Trial: 14 days") { viewModel.debugActions.setTrialDays(14) }
                Button("Set Trial: 7 days") { viewModel.debugActions.setTrialDays(7) }
                Button("Set Trial: 3 days") { viewModel.debugActions.setTrialDays(3) }
                Button("Set Trial: 1 day") { viewModel.debugActions.setTrialDays(1) }
                Divider()
                Button("Expire Trial") { viewModel.debugActions.expireTrial() }
                Button("Reset Trial") { viewModel.debugActions.resetTrial() }
                Divider()
                Button("Activate Test License") { viewModel.debugActions.setValidLicense() }
                Button("Clear License") { viewModel.debugActions.clearLicense() }
                Divider()
                Button("Print Debug Info") { viewModel.debugActions.printInfo() }
            }
            .buttonStyle(.plain)
            .font(MenuBarStyle.bodyFont)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MenuBarStyle.horizontalPadding)
            .padding(.vertical, MenuBarStyle.verticalPadding)
            #endif

            Divider()

            // Trial/license status at bottom (non-interactive)
            statusBannerContent

            Button("Quit Fullbright") {
                viewModel.quitApp()
            }
            .buttonStyle(.plain)
            .font(MenuBarStyle.bodyFont)
            .padding(.horizontal, MenuBarStyle.horizontalPadding)
            .padding(.vertical, MenuBarStyle.verticalPadding)
        }
        .frame(width: 220)
        .onAppear {
            viewModel.refreshAuthIfUnauthenticated()
        }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBannerContent: some View {
        switch viewModel.authState {
        case .trial(let daysRemaining, _):
            statusBanner(
                text: "Trial: \(daysRemaining) days left",
                color: viewModel.authState.isTrialUrgent ? .orange : .secondary
            )
            Divider()
        case .expired:
            statusBanner(text: "License Required", color: .red)
            Divider()
        default:
            EmptyView()
        }
    }

    private func statusBanner(text: String, color: Color) -> some View {
        HStack {
            Text(text)
                .font(MenuBarStyle.captionFont)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, MenuBarStyle.horizontalPadding)
        .padding(.vertical, MenuBarStyle.verticalPadding)
        .allowsHitTesting(false)
    }
}
