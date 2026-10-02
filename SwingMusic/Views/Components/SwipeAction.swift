import SwiftUI

struct PullAction {
    // Nil shows the icon on its own.
    var label: String?
    let icon: String
    let armedColor: Color
    let perform: () -> Void
}

// Pull a row right to reveal `leading`, or left to reveal `trailing`. The row resists the pull, the
// background turns the action's armed color once its content is fully revealed, and releasing while
// armed performs it. Haptics mark the start of the pull, crossing the threshold either way, and the
// confirmation.
struct PullActions: ViewModifier {
    let leading: PullAction?
    let trailing: PullAction?

    private enum Side { case leading, trailing }

    // Padding on each side of the revealed content; an action arms once its content shows with this much room around it.
    private static let contentInset: CGFloat = 18
    private static let idleColor = Color(.systemGray3)

    // Positive reveals the leading action, negative the trailing one.
    @State private var offset: CGFloat = 0
    @State private var armed = false
    // Decided on the drag's first movement, so a vertical scroll never turns into a pull halfway through.
    @State private var side: Side?
    @State private var decided = false
    @State private var leadingWidth: CGFloat = 110
    @State private var trailingWidth: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .leading) {
                if let leading { revealed(leading, width: max(0, offset), alignment: .leading) { leadingWidth = $0 } }
            }
            .background(alignment: .trailing) {
                if let trailing { revealed(trailing, width: max(0, -offset), alignment: .trailing) { trailingWidth = $0 } }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged(dragChanged)
                    .onEnded { _ in dragEnded() }
            )
    }

    private func revealed(_ item: PullAction, width: CGFloat, alignment: Alignment,
                          measured: @escaping (CGFloat) -> Void) -> some View {
        ZStack(alignment: alignment) {
            armed ? item.armedColor : Self.idleColor
            Group {
                if let label = item.label {
                    Label(label, systemImage: item.icon)
                } else {
                    Image(systemName: item.icon)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured($0) }
            .padding(alignment == .leading ? .leading : .trailing, Self.contentInset)
            .opacity(min(1, width / 40))
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: armed)
    }

    private func dragChanged(_ value: DragGesture.Value) {
        let dx = value.translation.width, dy = value.translation.height
        if !decided {
            decided = true
            if abs(dx) > abs(dy) {
                side = dx > 0 ? (leading == nil ? nil : .leading) : (trailing == nil ? nil : .trailing)
            }
            if side != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        guard let side else { return }

        let pulled = side == .leading ? max(0, dx) : max(0, -dx)
        let travel = Self.resisted(pulled)
        offset = side == .leading ? travel : -travel
        let nowArmed = travel >= armDistance(side)
        if nowArmed != armed {
            armed = nowArmed
            UIImpactFeedbackGenerator(style: nowArmed ? .medium : .light).impactOccurred()
        }
    }

    private func dragEnded() {
        if armed, let side, let item = side == .leading ? leading : trailing {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            item.perform()
        }
        side = nil
        decided = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            offset = 0
            armed = false
        }
    }

    // Distance the row has to travel, after resistance, before releasing performs the action.
    private func armDistance(_ side: Side) -> CGFloat {
        Self.contentInset + (side == .leading ? leadingWidth : trailingWidth) + Self.contentInset
    }

    // Rubber-band curve: close to the finger at first, then increasingly stiff the further it is pulled.
    static func resisted(_ distance: CGFloat) -> CGFloat {
        let range: CGFloat = 1000
        return distance * range / (range + distance)
    }
}

extension View {
    func pullActions(leading: PullAction? = nil, trailing: PullAction? = nil) -> some View {
        modifier(PullActions(leading: leading, trailing: trailing))
    }
}
