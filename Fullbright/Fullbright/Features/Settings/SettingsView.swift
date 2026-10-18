//
//  SettingsView.swift
//  Fullbright
//

import SwiftUI
import Sparkle

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    private let appVersion = Bundle.main.appVersion
    private static let currentYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        Form {
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
    }

    // MARK: - Sections

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
                    Text("Automatically check for updates")

                    Text("Checks for updates periodically in the background")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Check Now") {
                    viewModel.checkForUpdates()
                }

                Toggle("Automatically check for updates", isOn: $viewModel.automaticallyChecksForUpdates)
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                    .labelsHidden()
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
                Text("© \(Self.currentYear) Fullbright")
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
            Button("Show Onboarding") {
                viewModel.showOnboarding()
            }
        } header: {
            Text("Debug")
        }
    }
    #endif
}
