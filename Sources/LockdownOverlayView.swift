import SwiftUI

struct LockdownOverlayView: View {
    @EnvironmentObject private var sessionController: SessionController
    @State private var showingEmergencySheet = false

    let endDate: Date
    let message: String

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Text(message)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text(timeRemaining)
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text("Lockdown ends at \(endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))

                EmergencyHoldButton {
                    showingEmergencySheet = true
                }
                .padding(.top, 10)
            }
        }
        .sheet(isPresented: $showingEmergencySheet) {
            EmergencyExitView(challenge: sessionController.emergencyChallenge()) {
                showingEmergencySheet = false
                sessionController.completeEmergencyExit()
            }
        }
    }

    private var timeRemaining: String {
        let remaining = max(0, Int(endDate.timeIntervalSince(sessionController.now)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
