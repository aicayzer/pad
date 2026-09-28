import SwiftUI

struct DevelopmentBadge: View {
    var body: some View {
        #if DEBUG
        Text("DEV")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Development build")
        #endif
    }
}
