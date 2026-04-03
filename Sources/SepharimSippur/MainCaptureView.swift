import SwiftUI

struct MainCaptureView: View {
    @ObservedObject var model: AppModel

    private var visiblePhase: CapturePhase {
        if model.hasBlockingSetupFailure {
            return .error
        }

        if model.isBootstrappingDependencies {
            return .processing
        }

        return model.phase
    }

    private var isInteractive: Bool {
        if model.hasBlockingSetupFailure {
            return true
        }

        return model.isCaptureReady && visiblePhase.isInteractive
    }

    var body: some View {
        ZStack {
            CaptureCircleView(
                phase: visiblePhase,
                isEnabled: isInteractive
            )
        }
        .frame(width: CaptureCircleView.panelSize, height: CaptureCircleView.panelSize)
        .background(Color.clear)
    }
}
