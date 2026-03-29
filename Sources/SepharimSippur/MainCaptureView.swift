import SwiftUI

struct MainCaptureView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

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
                isEnabled: isInteractive,
                scale: settings.captureControlSize.contentScale
            )
        }
        .frame(
            width: settings.captureControlSize.panelSize,
            height: settings.captureControlSize.panelSize
        )
        .background(Color.clear)
    }
}
