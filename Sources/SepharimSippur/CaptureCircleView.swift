import SwiftUI

struct CaptureCircleView: View {
    let phase: CapturePhase
    let isEnabled: Bool
    let scale: CGFloat

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
                        startRadius: 10,
                        endRadius: 96
                    )
                )
                .frame(width: 156, height: 156)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
                .scaleEffect(phase.shouldPulse ? (pulse ? 1.08 : 0.93) : 1.0)

            Circle()
                .trim(from: phase.outerRingTrimRange.lowerBound, to: phase.outerRingTrimRange.upperBound)
                .stroke(
                    glowColor.opacity(ringOpacity),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: 172, height: 172)
                .rotationEffect(.degrees(phase.shouldSpinRing ? (spinRing ? 360 : 0) : 0))

            symbolView
        }
        .frame(width: 184, height: 184)
        .scaleEffect(scale)
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
            return Color(red: 0.90, green: 0.22, blue: 0.26)
        case .recording:
            return Color(red: 0.96, green: 0.18, blue: 0.22)
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
                .controlSize(.regular)
                .tint(.white)
                .scaleEffect(1.2)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        case .error:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 34, weight: .bold, design: .rounded))
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
