import SwiftUI

struct MenuBarIconView: View {
    var body: some View {
        if let icon = BrandImageLoader.menuBarStatusIcon() {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "mic.fill")
        }
    }
}
