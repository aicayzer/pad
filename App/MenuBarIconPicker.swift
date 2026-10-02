import SwiftUI

struct MenuBarIconPicker: View {
    @Binding var selection: MenuBarIcon

    var body: some View {
        Picker("Menu bar icon", selection: $selection) {
            ForEach(MenuBarIcon.allCases) { icon in
                Label {
                    Text(icon.title)
                } icon: {
                    icon.image
                }
                .tag(icon)
            }
        }
        .tint(.primary)
        .accessibilityIdentifier("menuBarIcon")
    }
}
