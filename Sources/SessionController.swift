import AppKit
import Combine
import SwiftUI

enum SessionState: String, Codable {
    case idle
    case armed
    case lockdown
}

struct LockdownSession: Codable {
    let id: UUID
    let createdAt: Date
    let lockdownStartsAt: Date
    let lockdownEndsAt: Date
    let muteAudio: Bool
    var state: SessionState
}

@MainActor
final class SessionController: NSObject, ObservableObject {
    @Published var startAfterMinutesText = "30"
    @Published var startAfterSecondsText = "00"
    @Published var lockdownMinutesText = "5"
    @Published var lockdownSecondsText = "00"
    @Published var muteAudio = true
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var now = Date()
    @Published private(set) var activeSession: LockdownSession?
    @Published var quitAttemptMessage: String?

    private let overlayManager = OverlayWindowManager()
    private let audioController = AudioController()
    private var clockTimer: Timer?
    private var displayObserver: NSObjectProtocol?

    private let emergencyPrompts = [
        "I am ending this break early and I accept that the session will stop now.",
        "A short interruption is better than abandoning the break without thinking first.",
        "If this is a real emergency, I can continue and close the app after this challenge."
    ]

    override init() {
        super.init()
        startClock()
        observeDisplays()
    }

    deinit {
        clockTimer?.invalidate()
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }
    }

    func startSession() {
        normalizeDurationInputs()

        let startAfterSeconds = max(1, parsedDuration(minutes: startAfterMinutesText, seconds: startAfterSecondsText))
        let lockdownSeconds = max(1, parsedDuration(minutes: lockdownMinutesText, seconds: lockdownSecondsText))
        let createdAt = Date()
        let startDate = createdAt.addingTimeInterval(TimeInterval(startAfterSeconds))
        let endDate = startDate.addingTimeInterval(TimeInterval(lockdownSeconds))

        activeSession = LockdownSession(
            id: UUID(),
            createdAt: createdAt,
            lockdownStartsAt: startDate,
            lockdownEndsAt: endDate,
            muteAudio: muteAudio,
            state: .armed
        )
        state = .armed
        quitAttemptMessage = nil
        overlayManager.dismissAll()
    }

    func cancelSession() {
        finishSession(resetMessage: true)
    }

    func handleQuitRequest() {
        if state == .lockdown {
            quitAttemptMessage = "Normal quit is disabled during lockdown. Use the emergency flow or system force quit if needed."
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.terminate(nil)
    }

    func remainingCountdownText() -> String {
        guard let session = activeSession else {
            return "Ready"
        }

        switch state {
        case .idle:
            return "Ready"
        case .armed:
            return "Lockdown starts in \(formattedDuration(until: session.lockdownStartsAt))"
        case .lockdown:
            return "Lockdown active: \(formattedDuration(until: session.lockdownEndsAt)) remaining"
        }
    }

    func emergencyChallenge() -> EmergencyExitChallenge {
        EmergencyExitChallenge(sentences: Array(emergencyPrompts.shuffled().prefix(2)))
    }

    func completeEmergencyExit() {
        finishSession(resetMessage: false)
    }

    func normalizeTypedDurations() {
        normalizeDurationInputs()
    }

    func reassertLockdownWindowsIfNeeded() {
        guard let session = activeSession, state == .lockdown else {
            return
        }

        overlayManager.presentLockdown(sessionController: self, endDate: session.lockdownEndsAt)
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        if state == .lockdown {
            quitAttemptMessage = "Normal quit is disabled during lockdown. Use the emergency flow or system force quit if needed."
            NSApp.activate(ignoringOtherApps: true)
            return .terminateCancel
        }

        return .terminateNow
    }

    private func startClock() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        clockTimer?.tolerance = 0.2
    }

    private func tick() {
        now = Date()

        guard var session = activeSession else {
            return
        }

        switch state {
        case .idle:
            return
        case .armed:
            if now >= session.lockdownStartsAt {
                session.state = .lockdown
                activeSession = session
                state = .lockdown

                if session.muteAudio {
                    audioController.muteSystemAudio()
                }

                overlayManager.presentLockdown(
                    sessionController: self,
                    endDate: session.lockdownEndsAt
                )
                NSApp.activate(ignoringOtherApps: true)
            }
        case .lockdown:
            overlayManager.update(endDate: session.lockdownEndsAt)
            if now >= session.lockdownEndsAt {
                finishSession(resetMessage: true)
            }
        }
    }

    private func finishSession(resetMessage: Bool) {
        audioController.restoreSystemAudioIfNeeded()
        overlayManager.dismissAll()
        activeSession = nil
        state = .idle
        if resetMessage {
            quitAttemptMessage = nil
        }
    }

    private func observeDisplays() {
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileDisplays()
            }
        }
    }

    private func reconcileDisplays() {
        guard let session = activeSession, state == .lockdown else {
            return
        }

        overlayManager.presentLockdown(sessionController: self, endDate: session.lockdownEndsAt)
    }

    private func formattedDuration(until endDate: Date) -> String {
        let remaining = max(0, Int(endDate.timeIntervalSince(now)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func normalizeDurationInputs() {
        let normalizedStart = normalizedComponents(minutes: startAfterMinutesText, seconds: startAfterSecondsText)
        startAfterMinutesText = normalizedStart.minutes
        startAfterSecondsText = normalizedStart.seconds

        let normalizedLockdown = normalizedComponents(minutes: lockdownMinutesText, seconds: lockdownSecondsText)
        lockdownMinutesText = normalizedLockdown.minutes
        lockdownSecondsText = normalizedLockdown.seconds
    }

    private func parsedDuration(minutes: String, seconds: String) -> Int {
        let minuteValue = Int(minutes) ?? 0
        let secondValue = Int(seconds) ?? 0
        return (max(0, minuteValue) * 60) + max(0, secondValue)
    }

    private func normalizedComponents(minutes: String, seconds: String) -> (minutes: String, seconds: String) {
        let totalSeconds = max(1, parsedDuration(minutes: sanitizedMinuteString(minutes), seconds: sanitizedSecondString(seconds)))
        let normalizedMinutes = totalSeconds / 60
        let normalizedSeconds = totalSeconds % 60
        return (String(normalizedMinutes), String(format: "%02d", normalizedSeconds))
    }

    private func sanitizedMinuteString(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? "0" : String(digits.prefix(3))
    }

    private func sanitizedSecondString(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else {
            return "0"
        }
        let trimmed = String(digits.prefix(2))
        return String(min(Int(trimmed) ?? 0, 59))
    }
}
