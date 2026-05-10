import SwiftUI

struct EmergencyHoldButton: View {
    let onCompleted: () -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var startedAt: Date?
    @State private var hasTriggeredCompletion = false

    private let requiredDuration: TimeInterval = 8

    var body: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: 96, height: 10)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 96 * progress)
                }
                .overlay {
                    Text("Hold to exit")
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
                        hasTriggeredCompletion = false
                    }
                    isPressing = true
                    updateProgress()
                }
                .onEnded { _ in
                    isPressing = false
                    progress = 0
                    startedAt = nil
                    hasTriggeredCompletion = false
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

        guard progress >= 1, !hasTriggeredCompletion else {
            return
        }

        hasTriggeredCompletion = true
        isPressing = false
        self.progress = 0
        self.startedAt = nil
        onCompleted()
    }
}
