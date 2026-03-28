import SwiftUI

struct MainCaptureView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var panelController: CapturePanelController
    @State private var suppressTap = false

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

    private var action: () -> Void {
        if model.hasBlockingSetupFailure {
            return model.retryDependencyBootstrap
        }

        return model.requestCaptureToggle
    }

    private var tapAction: () -> Void {
        {
            if suppressTap {
                suppressTap = false
                return
            }

            action()
        }
    }

    var body: some View {
        ZStack {
            CaptureCircleView(
                phase: visiblePhase,
                isEnabled: isInteractive,
                action: tapAction
            )
        }
        .frame(width: 184, height: 184)
        .background(Color.clear)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    suppressTap = true
                    panelController.beginDragIfNeeded()
                    panelController.updateDrag(translation: value.translation)
                }
                .onEnded { _ in
                    panelController.endDrag()

                    DispatchQueue.main.async {
                        suppressTap = false
                    }
                }
        )
    }
}
