import SwiftUI

struct EmergencyHoldButton: View {
    let onCompleted: () -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var startedAt: Date?

    private let requiredDuration: TimeInterval = 8

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(progress >= 0.01 ? "Hold to unlock emergency exit" : "")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))

            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: 96, height: 10)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 96 * progress)
                }
                .overlay {
                    Text("Emergency Exit")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                        .offset(y: -14)
                }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if startedAt == nil {
                        startedAt = Date()
                    }
                    isPressing = true
                    updateProgress()
                }
                .onEnded { _ in
                    let completed = progress >= 1
                    isPressing = false
                    progress = 0
                    startedAt = nil
                    if completed {
                        onCompleted()
                    }
                }
        )
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            guard isPressing else {
                return
            }
            updateProgress()
        }
    }

    private func updateProgress() {
        guard let startedAt else {
            progress = 0
            return
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        progress = min(1, CGFloat(elapsed / requiredDuration))
    }
}
