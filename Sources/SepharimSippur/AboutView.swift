import SwiftUI
import AppKit

struct AboutView: View {
    private var appIcon: NSImage? {
        BrandImageLoader.applicationIcon() ?? NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 14) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(spacing: 6) {
                Text(AppMetadata.appName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }

            Text("v\(AppMetadata.versionString) (\(AppMetadata.buildString))")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            Text(AppMetadata.copyrightString)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(width: 320, height: 240)
    }
}
