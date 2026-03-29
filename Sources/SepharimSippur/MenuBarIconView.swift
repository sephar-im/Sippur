import SwiftUI

struct MenuBarIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let menuBarIcon = BrandImageLoader.menuBarIcon(for: iconVariant) {
            Image(nsImage: menuBarIcon)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .frame(width: 14, height: 14)
        } else {
            Text("SS")
        }
    }

    private var iconVariant: MenuBarIconVariant {
        colorScheme == .dark ? .darkMode : .lightMode
    }
}
