import SwiftUI

struct SwipeAction: ViewModifier {
    let action: () -> Void
    let label: String
    let willFireLabel: String
    let icon: String
    let color: Color
    @State private var offset: CGFloat = 0
    @State private var willFire = false

    func body(content: Content) -> some View {
        ZStack {

            HStack {
                ZStack {
                    color
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .scaleEffect(willFire ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: willFire)

                        if offset > 80 {
                            Text(willFire ? willFireLabel : label)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: max(0, offset))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: willFire)

            content

                .offset(x: offset)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 30, coordinateSpace: .local)
                        .onChanged { value in
                            if value.translation.width > 0 && abs(value.translation.width) > abs(value.translation.height) {
                                offset = value.translation.width
                                willFire = offset > 110
                            }
                        }
                        .onEnded { value in
                            if willFire {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    offset = 0
                                    willFire = false
                                }
                                action()
                            } else {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    offset = 0
                                    willFire = false
                                }
                            }
                        }
                )
        }
    }
}
