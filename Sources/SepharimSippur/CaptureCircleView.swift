import SwiftUI

struct CaptureCircleView: View {
    static let panelSize: CGFloat = 104

    let phase: CapturePhase
    let isEnabled: Bool

    @State private var pulse = false
    @State private var spinRing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            baseFillColor.opacity(0.98),
                            baseFillColor.opacity(0.82),
                            Color.black.opacity(0.92),
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 54
                    )
                )
                .frame(width: 88, height: 88)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
                .scaleEffect(phase.shouldPulse ? (pulse ? 1.08 : 0.93) : 1.0)

            Circle()
                .trim(from: phase.outerRingTrimRange.lowerBound, to: phase.outerRingTrimRange.upperBound)
                .stroke(
                    glowColor.opacity(ringOpacity),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 98, height: 98)
                .rotationEffect(.degrees(phase.shouldSpinRing ? (spinRing ? 360 : 0) : 0))

            symbolView
        }
        .frame(width: Self.panelSize, height: Self.panelSize)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.88)
        .animation(.easeInOut(duration: 0.24), value: phase)
        .onAppear {
            updateAnimation(for: phase)
        }
        .onChange(of: phase) { _, newPhase in
            updateAnimation(for: newPhase)
        }
    }

    private var baseFillColor: Color {
        switch phase {
        case .idle:
            return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .recording:
            return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .processing:
            return Color(red: 0.92, green: 0.66, blue: 0.20)
        case .success:
            return Color(red: 0.24, green: 0.76, blue: 0.48)
        case .error:
            return Color(red: 0.91, green: 0.36, blue: 0.22)
        }
    }

    private var glowColor: Color {
        phase.accentColor
    }

    private var ringOpacity: Double {
        switch phase {
        case .idle:
            return 0.0
        case .recording:
            return 0.54
        case .processing:
            return 0.9
        case .success:
            return 0.4
        case .error:
            return 0.42
        }
    }

    @ViewBuilder
    private var symbolView: some View {
        switch phase {
        case .processing:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .scaleEffect(0.95)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        case .error:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        case .idle, .recording:
            EmptyView()
        }
    }

    private func updateAnimation(for phase: CapturePhase) {
        if phase.shouldPulse {
            pulse = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            pulse = false
        }

        if phase.shouldSpinRing {
            spinRing = false
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                spinRing = true
            }
        } else {
            spinRing = false
        }
    }
}
