//
//  XDRBrightnessOSDView.swift
//  Fullbright
//

import SwiftUI

enum OSDLayout {
    static let width: CGFloat = 290
    static let height: CGFloat = 62
    static let tipHeight: CGFloat = 24
    static let tipSpacing: CGFloat = 16
    static let verticalPadding: CGFloat = 6
    static let horizontalPadding: CGFloat = 20
    static let windowTrailingMargin: CGFloat = 26
    static let windowTopMargin: CGFloat = 10
}

struct XDRBrightnessOSDView: View {
    @Bindable var osd: XDRBrightnessOSDState
    @State private var sliding = false

    private static let steps: [Float] = stride(from: 0.0, through: 1.0, by: 0.0625).map { Float($0) }

    var body: some View {
        VStack(spacing: OSDLayout.tipSpacing) {
            brightnessCard
                .brightness(1.5)
                .frame(width: OSDLayout.width, height: OSDLayout.height)
                .background(
                    GlassEffectBackground(variant: 6, scrimState: 0, subduedState: 0, cornerRadius: 24)
                        .brightness(-0.3)
                )
                .background(Material.ultraThin.materialActiveAppearance(.active).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            if let tipString = osd.tip {
                Text(tipString)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .frame(height: OSDLayout.tipHeight)
                    .background(
                        VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow, state: .active)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
                    .fixedSize()
                    .transition(.scale.animation(.spring(response: 0.3, dampingFraction: 0.7)))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var slider: some View {
        SwiftUI.Slider(value: $osd.value) {} ticks: {
            SliderTickContentForEach(Self.steps, id: \.self) { value in
                SliderTick(value)
            }
        } onEditingChanged: { editing in
            sliding = editing
        }
        .tint(.white)
        .onChange(of: osd.value) { oldValue, newValue in
            guard sliding else { return }
            osd.onChange?(newValue)
        }
        .disabled(osd.locked)
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(osd.value * 100)) percent")
    }

    private var brightnessCard: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(osd.leadingLabel)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(osd.text.isEmpty ? "\(Int(osd.value * 100))%" : osd.text)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                if osd.locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .accessibilityLabel("Brightness locked")
                }
            }
            HStack {
                if let imageLeft = osd.leadingIcon {
                    Image(systemName: imageLeft)
                        .foregroundStyle(.white.opacity(0.8))
                }
                slider
                Image(systemName: osd.image)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, OSDLayout.horizontalPadding)
        .padding(.vertical, OSDLayout.verticalPadding)
        .frame(width: OSDLayout.width, height: OSDLayout.height, alignment: .center)
        .fixedSize()
    }
}
