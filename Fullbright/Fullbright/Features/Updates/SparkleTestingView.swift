//
//  SparkleTestingView.swift
//  Fullbright
//

#if DEBUG
import SwiftUI
import Sparkle

struct SparkleTestingView: View {
    private let updater: SPUUpdater
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    @State private var simulatedVersion = "1.0.0"
    @State private var simulatedBuild = "1"
    @State private var releaseNotes = "Bug fixes and performance improvements"
    @State private var showingVersionSimulator = false
    @State private var debugLog: [DebugLogEntry] = []

    struct DebugLogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
        let type: LogType

        enum LogType {
            case info, success, warning, error
        }
    }

    init(updater: SPUUpdater) {
        self.updater = updater
        self._automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
        self._automaticallyDownloadsUpdates = State(initialValue: updater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Sparkle Testing")
                    .font(.largeTitle.weight(.bold))

                Text("Current Version: \(Bundle.main.appVersion) (\(Bundle.main.buildNumber ?? "?"))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()

            ScrollView {
                VStack(spacing: 20) {
                    settingsSection
                    versionSimulatorSection
                    actionsSection
                    debugLogSection
                }
                .padding()
            }
        }
        .frame(minWidth: 400, idealWidth: 500, maxWidth: .infinity, minHeight: 500, idealHeight: 700, maxHeight: .infinity)
        .sheet(isPresented: $showingVersionSimulator) {
            VersionSimulatorSheet(
                version: $simulatedVersion,
                build: $simulatedBuild,
                releaseNotes: $releaseNotes,
                onSimulate: { version, build, notes in
                    simulateVersion(version, build: build, notes: notes)
                }
            )
        }
        .onAppear {
            addLog("Testing interface loaded", type: .success)
            refreshStatus()
        }
    }

    // MARK: - Sections

    private var settingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Update Settings", systemImage: "gearshape")
                    .font(.headline)

                Divider()

                Toggle(isOn: Binding(
                    get: { automaticallyChecksForUpdates },
                    set: { newValue in
                        automaticallyChecksForUpdates = newValue
                        updater.automaticallyChecksForUpdates = newValue
                        addLog("Automatic checks: \(newValue ? "enabled" : "disabled")", type: .info)
                    }
                )) {
                    Text("Automatically check for updates")
                        .font(.body)
                }

                Toggle(isOn: Binding(
                    get: { automaticallyDownloadsUpdates },
                    set: { newValue in
                        automaticallyDownloadsUpdates = newValue
                        updater.automaticallyDownloadsUpdates = newValue
                        addLog("Automatic downloads: \(newValue ? "enabled" : "disabled")", type: .info)
                    }
                )) {
                    Text("Automatically download updates")
                        .font(.body)
                }

                HStack {
                    Text("Check interval:")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(updater.updateCheckInterval / 3600)) hours")
                        .font(.body.monospacedDigit())
                }

                if let lastCheck = updater.lastUpdateCheckDate {
                    HStack {
                        Text("Last check:")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .font(.body)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var versionSimulatorSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Version Simulator", systemImage: "wand.and.stars")
                    .font(.headline)

                Divider()

                Button(action: { showingVersionSimulator = true }) {
                    Label("Create Test Version...", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([
                            ("0.0.1", "Very Old"),
                            ("0.9.0", "Previous"),
                            ("1.0.0", "Current")
                        ], id: \.0) { version, label in
                            Button(action: {
                                simulateVersion(version, build: "1")
                            }) {
                                VStack(spacing: 4) {
                                    Text(version)
                                        .font(.system(.caption, design: .monospaced))
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var actionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Testing Actions", systemImage: "play.circle")
                    .font(.headline)

                Divider()

                HStack(spacing: 12) {
                    Button(action: checkForUpdates) {
                        Label("Check Now", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: checkSilently) {
                        Label("Silent Check", systemImage: "arrow.down.circle.dotted")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                HStack(spacing: 12) {
                    Button(action: viewAppcast) {
                        Label("View Feed", systemImage: "doc.text")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button(action: resetCycle) {
                        Label("Reset Cycle", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive, action: clearAllSettings) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var debugLogSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Debug Log", systemImage: "terminal")
                        .font(.headline)

                    Spacer()

                    Button(action: { debugLog.removeAll() }) {
                        Image(systemName: "clear")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if debugLog.isEmpty {
                            Text("No activity yet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(debugLog) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: iconForLogType(entry.type))
                                        .font(.caption)
                                        .foregroundStyle(colorForLogType(entry.type))
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.message)
                                            .font(.system(.caption, design: .default))

                                        Text(entry.timestamp, style: .time)
                                            .font(.system(.caption2, design: .default))
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 150)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func checkForUpdates() {
        addLog("Checking for updates...", type: .info)
        updater.checkForUpdates()
    }

    private func checkSilently() {
        addLog("Checking for updates silently...", type: .info)
        updater.checkForUpdatesInBackground()
    }

    private func viewAppcast() {
        guard let feedURL = updater.feedURL else {
            addLog("No feed URL configured", type: .error)
            return
        }
        addLog("Opening appcast: \(feedURL.absoluteString)", type: .info)
        NSWorkspace.shared.open(feedURL)
    }

    private func resetCycle() {
        updater.resetUpdateCycle()
        addLog("Update cycle reset", type: .success)
    }

    private func clearAllSettings() {
        let keys = [
            "SUEnableAutomaticChecks",
            "SUHasLaunchedBefore",
            "SULastCheckTime",
            "SUSkippedVersion",
            "SUUpdateRelaunchingMarker",
            "SUUpdateGroupIdentifier"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        addLog("All Sparkle settings cleared", type: .warning)
    }

    /// Note: Writing CFBundle keys to UserDefaults does NOT affect Bundle.main.infoDictionary.
    /// This is for Sparkle UI testing only — Sparkle may read these as overrides.
    private func simulateVersion(_ version: String, build: String, notes: String = "") {
        UserDefaults.standard.set(version, forKey: "CFBundleShortVersionString")
        UserDefaults.standard.set(build, forKey: "CFBundleVersion")
        if !notes.isEmpty {
            UserDefaults.standard.set(notes, forKey: "SimulatedReleaseNotes")
        }
        addLog("Simulating version \(version) (\(build))", type: .success)
    }

    private func refreshStatus() {
        addLog("Auto-check: \(updater.automaticallyChecksForUpdates)", type: .info)
        addLog("Auto-download: \(updater.automaticallyDownloadsUpdates)", type: .info)
        if let feedURL = updater.feedURL {
            addLog("Feed URL: \(feedURL.absoluteString)", type: .info)
        }
    }

    private func addLog(_ message: String, type: DebugLogEntry.LogType) {
        debugLog.append(DebugLogEntry(message: message, type: type))
    }

    private func iconForLogType(_ type: DebugLogEntry.LogType) -> String {
        switch type {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private func colorForLogType(_ type: DebugLogEntry.LogType) -> Color {
        switch type {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct VersionSimulatorSheet: View {
    @Binding var version: String
    @Binding var build: String
    @Binding var releaseNotes: String
    let onSimulate: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset = "custom"

    var body: some View {
        VStack(spacing: 20) {
            Text("Simulate New Version")
                .font(.title2.weight(.semibold))

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Preset", selection: $selectedPreset) {
                        Text("Custom").tag("custom")
                        Text("Patch (1.1.1)").tag("patch")
                        Text("Minor (1.2.0)").tag("minor")
                        Text("Major (2.0.0)").tag("major")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPreset) { _, newValue in
                        switch newValue {
                        case "patch":
                            version = "1.1.1"
                            releaseNotes = "\u{2022} Fixed crash when switching XDR modes\n\u{2022} Improved performance\n\u{2022} Minor UI tweaks"
                        case "minor":
                            version = "1.2.0"
                            releaseNotes = "\u{2022} Added keyboard shortcuts\n\u{2022} New preset management\n\u{2022} Better display detection\n\u{2022} Bug fixes"
                        case "major":
                            version = "2.0.0"
                            releaseNotes = "\u{2022} Completely redesigned UI\n\u{2022} Multi-display support\n\u{2022} Advanced color profiles\n\u{2022} Performance improvements\n\u{2022} Many bug fixes"
                        default:
                            break
                        }
                    }

                    Divider()

                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Version")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("1.2.0", text: $version)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading) {
                            Text("Build")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("123", text: $build)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Release Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $releaseNotes)
                            .font(.body)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(4)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Simulate") {
                    onSimulate(version, build, releaseNotes)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 450, height: 400)
    }
}
#endif
