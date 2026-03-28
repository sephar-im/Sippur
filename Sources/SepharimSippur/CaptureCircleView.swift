import SwiftUI

struct CaptureCircleView: View {
    let phase: CapturePhase
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(phase.accentColor.opacity(0.28), lineWidth: 22)
                    .frame(width: 240, height: 240)
                    .scaleEffect(phase.shouldPulse ? (pulse ? 1.10 : 0.90) : 1.0)
                    .opacity(phase.shouldPulse ? (pulse ? 0.08 : 0.40) : 0.18)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                phase.accentColor.opacity(0.96),
                                phase.accentColor.opacity(0.70),
                                Color.black.opacity(0.90),
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 140
                        )
                    )
                    .frame(width: 184, height: 184)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: phase.accentColor.opacity(0.45), radius: 28, y: 12)

                symbolView
            }
            .frame(width: 260, height: 260)
        }
        .buttonStyle(.plain)
        .disabled(!phase.isInteractive)
        .animation(.easeInOut(duration: 0.28), value: phase)
        .onAppear {
            updateAnimation(for: phase)
        }
        .onChange(of: phase) { _, newPhase in
            updateAnimation(for: newPhase)
        }
    }

    @ViewBuilder
    private var symbolView: some View {
        switch phase {
        case .processing:
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .scaleEffect(1.25)
        default:
            Image(systemName: phase.symbolName)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
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
    }
}
