import SwiftUI

struct MainCaptureView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.16),
                    Color(red: 0.14, green: 0.16, blue: 0.20),
                    Color(red: 0.08, green: 0.10, blue: 0.13),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                CaptureCircleView(
                    phase: model.phase,
                    action: model.handlePrimaryAction
                )

                VStack(spacing: 8) {
                    Text(model.phase.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(model.statusText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .multilineTextAlignment(.center)

                    Text(model.detailText)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 280)

                Text("Click once to record. Click again to stop and save a placeholder note.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)

                Spacer()
            }
            .padding(32)
        }
    }
}
