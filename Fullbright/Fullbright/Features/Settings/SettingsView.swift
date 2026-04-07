//
//  SettingsView.swift
//  Fullbright
//

import SwiftUI
import Sparkle

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    private let appVersion = Bundle.main.appVersion

    var body: some View {
        Form {
            licenseSection
            generalSection
            updatesSection
            aboutSection

            #if DEBUG
            debugSection
            #endif
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: WindowSize.settingsWidth, minHeight: WindowSize.settingsHeight)
        .alert(
            viewModel.alertState?.title ?? "",
            isPresented: Binding(
                get: { viewModel.alertState != nil },
                set: { if !$0 { viewModel.alertState = nil } }
            )
        ) {
            Button("OK") { viewModel.alertState = nil }
        } message: {
            if let message = viewModel.alertState?.message {
                Text(message)
            }
        }
    }

    // MARK: - Sections

    private var licenseSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                switch viewModel.authState {
                case .authenticated(let licenseId):
                    Label("Licensed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(licenseId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)

                case .trial(let daysRemaining, let expiryDate):
                    Text("Trial - \(daysRemaining) days remaining")
                        .foregroundStyle(viewModel.authState.trialColor)
                    Text("Expires \(expiryDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .expired:
                    Label("No Active License", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                case .notAuthenticated:
                    Text("Not Activated")
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.isAuthenticated {
                HStack {
                    TextField("License Key", text: $viewModel.licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isActivating)

                    Button("Activate") {
                        Task {
                            await viewModel.activateLicense()
                        }
                    }
                    .disabled(viewModel.licenseKey.isEmpty || viewModel.isActivating)

                    if viewModel.isActivating {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                HStack {
                    Spacer()
                    Button("Purchase Lifetime License") {
                        viewModel.purchaseLicense()
                    }
                    .buttonStyle(.link)
                }
            }
        } header: {
            Text("License")
        }
    }

    private var generalSection: some View {
        Section {
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
                .toggleStyle(.switch)

            Toggle("Show in Dock", isOn: $viewModel.showInDock)
                .toggleStyle(.switch)

            Text("When disabled, Fullbright runs only in the menu bar")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("General")
        }
    }

    private var updatesSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Automatically check for updates", isOn: $viewModel.automaticallyChecksForUpdates)
                    .toggleStyle(.switch)
                    .tint(.accentColor)

                    Text("Checks for updates periodically in the background")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Check Now") {
                    viewModel.checkForUpdates()
                }
            }

            Toggle("Automatically download updates", isOn: $viewModel.automaticallyDownloadsUpdates)
            .toggleStyle(.switch)
            .tint(.accentColor)
        } header: {
            Text("Updates")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appVersion)
                    .fontDesign(.monospaced)
            }

            HStack {
                Text("© \(Calendar.current.component(.year, from: Date())) Fullbright")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } header: {
            Text("About")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            HStack {
                Button("Set Test License") { viewModel.debugActions.setValidLicense() }
                Button("Clear License") { viewModel.debugActions.clearLicense() }
                Button("Reset Trial") { viewModel.debugActions.resetTrial() }
                Button("Show Onboarding") {
                    viewModel.showOnboarding()
                }
            }
        } header: {
            Text("Debug")
        }
    }
    #endif
}
