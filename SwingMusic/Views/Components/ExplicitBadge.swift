import SwiftUI

struct ExplicitBadge: View {
    var body: some View {
        Image(systemName: "e.square.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Explicit")
    }
}

extension View {
    func explicitBadge(_ explicit: Bool) -> some View {
        HStack(spacing: 5) {
            self
            if explicit { ExplicitBadge().layoutPriority(1) }
        }
    }
}
