//
//  OnboardingSimpleView.swift
//  Fullbright
//

import SwiftUI

struct OnboardingSimpleView: View {
    var onComplete: () -> Void = {}

    @State private var currentStep = Step.welcome

    private enum Step {
        case welcome
        case complete
    }

    var body: some View {
        VStack(spacing: 20) {
            switch currentStep {
            case .welcome:
                welcomeStep
            case .complete:
                completeStep
            }
        }
        .padding(40)
        .frame(width: WindowSize.settingsWidth, height: WindowSize.settingsHeight)
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Welcome to Fullbright")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Unlock your display's full brightness potential")
                .font(.body)
                .foregroundStyle(.secondary)

            Button("Continue") {
                currentStep = .complete
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Use the menu bar icon to control XDR brightness")
                .font(.body)
                .foregroundStyle(.secondary)

            Button("Get Started") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
