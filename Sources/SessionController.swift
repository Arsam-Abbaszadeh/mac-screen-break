import AppKit
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
    let overlayMessage: String
    var state: SessionState
}

private struct PersistedSettings: Codable {
    var startAfterHoursText: String
    var startAfterMinutesText: String
    var startAfterSecondsText: String
    var lockdownHoursText: String
    var lockdownMinutesText: String
    var lockdownSecondsText: String
    var overlayMessage: String
    var muteAudio: Bool
}

@MainActor
final class SessionController: NSObject, ObservableObject {
    @Published var startAfterHoursText = "0"
    @Published var startAfterMinutesText = "30"
    @Published var startAfterSecondsText = "00"
    @Published var lockdownHoursText = "0"
    @Published var lockdownMinutesText = "5"
    @Published var lockdownSecondsText = "00"
    @Published var overlayMessage = "Look away from the screen"
    @Published var muteAudio = true
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var now = Date()
    @Published private(set) var activeSession: LockdownSession?
    @Published var quitAttemptMessage: String?

    private let overlayManager = OverlayWindowManager()
    private let audioController = AudioController()
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "PersistedSettings"
    private var clockTimer: Timer?
    private var displayObserver: NSObjectProtocol?

    override init() {
        super.init()
        loadPersistedSettings()
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

        let startAfterSeconds = max(1, parsedDuration(hours: startAfterHoursText, minutes: startAfterMinutesText, seconds: startAfterSecondsText))
        let lockdownSeconds = max(1, parsedDuration(hours: lockdownHoursText, minutes: lockdownMinutesText, seconds: lockdownSecondsText))
        let createdAt = Date()
        let startDate = createdAt.addingTimeInterval(TimeInterval(startAfterSeconds))
        let endDate = startDate.addingTimeInterval(TimeInterval(lockdownSeconds))

        activeSession = LockdownSession(
            id: UUID(),
            createdAt: createdAt,
            lockdownStartsAt: startDate,
            lockdownEndsAt: endDate,
            muteAudio: muteAudio,
            overlayMessage: normalizedOverlayMessage,
            state: .armed
        )
        state = .armed
        quitAttemptMessage = nil
        overlayManager.dismissAll()
        persistSettings()
    }

    func startSessionImmediately() {
        normalizeDurationInputs()

        let lockdownSeconds = max(1, parsedDuration(hours: lockdownHoursText, minutes: lockdownMinutesText, seconds: lockdownSecondsText))
        let createdAt = Date()

        activeSession = LockdownSession(
            id: UUID(),
            createdAt: createdAt,
            lockdownStartsAt: createdAt,
            lockdownEndsAt: createdAt.addingTimeInterval(TimeInterval(lockdownSeconds)),
            muteAudio: muteAudio,
            overlayMessage: normalizedOverlayMessage,
            state: .lockdown
        )
        state = .lockdown
        quitAttemptMessage = nil
        overlayManager.dismissAll()

        if muteAudio {
            audioController.muteSystemAudio()
        }

        overlayManager.presentLockdown(
            sessionController: self,
            endDate: activeSession?.lockdownEndsAt ?? createdAt
        )
        NSApp.activate(ignoringOtherApps: true)
        persistSettings()
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

    func completeEmergencyExit() {
        finishSession(resetMessage: false)
    }

    func normalizeTypedDurations() {
        normalizeDurationInputs()
        persistSettings()
    }

    func persistEditableSettings() {
        persistSettings()
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
        let hours = remaining / 3600
        let minutes = remaining / 60
        let seconds = remaining % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, (remaining % 3600) / 60, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func normalizeDurationInputs() {
        let normalizedStart = normalizedComponents(hours: startAfterHoursText, minutes: startAfterMinutesText, seconds: startAfterSecondsText)
        startAfterHoursText = normalizedStart.hours
        startAfterMinutesText = normalizedStart.minutes
        startAfterSecondsText = normalizedStart.seconds

        let normalizedLockdown = normalizedComponents(hours: lockdownHoursText, minutes: lockdownMinutesText, seconds: lockdownSecondsText)
        lockdownHoursText = normalizedLockdown.hours
        lockdownMinutesText = normalizedLockdown.minutes
        lockdownSecondsText = normalizedLockdown.seconds
    }

    private func loadPersistedSettings() {
        guard
            let data = userDefaults.data(forKey: settingsKey),
            let persisted = try? JSONDecoder().decode(PersistedSettings.self, from: data)
        else {
            return
        }

        startAfterHoursText = persisted.startAfterHoursText
        startAfterMinutesText = persisted.startAfterMinutesText
        startAfterSecondsText = persisted.startAfterSecondsText
        lockdownHoursText = persisted.lockdownHoursText
        lockdownMinutesText = persisted.lockdownMinutesText
        lockdownSecondsText = persisted.lockdownSecondsText
        overlayMessage = persisted.overlayMessage
        muteAudio = persisted.muteAudio
        normalizeDurationInputs()
    }

    private func persistSettings() {
        let persisted = PersistedSettings(
            startAfterHoursText: startAfterHoursText,
            startAfterMinutesText: startAfterMinutesText,
            startAfterSecondsText: startAfterSecondsText,
            lockdownHoursText: lockdownHoursText,
            lockdownMinutesText: lockdownMinutesText,
            lockdownSecondsText: lockdownSecondsText,
            overlayMessage: overlayMessage,
            muteAudio: muteAudio
        )

        guard let data = try? JSONEncoder().encode(persisted) else {
            return
        }

        userDefaults.set(data, forKey: settingsKey)
    }

    private var normalizedOverlayMessage: String {
        let trimmed = overlayMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Look away from the screen" : trimmed
    }

    private func parsedDuration(hours: String, minutes: String, seconds: String) -> Int {
        let hourValue = Int(hours) ?? 0
        let minuteValue = Int(minutes) ?? 0
        let secondValue = Int(seconds) ?? 0
        return (max(0, hourValue) * 3600) + (max(0, minuteValue) * 60) + max(0, secondValue)
    }

    private func normalizedComponents(hours: String, minutes: String, seconds: String) -> (hours: String, minutes: String, seconds: String) {
        let totalSeconds = max(1, parsedDuration(
            hours: sanitizedHourString(hours),
            minutes: sanitizedMinuteString(minutes),
            seconds: sanitizedSecondString(seconds)
        ))
        let normalizedHours = totalSeconds / 3600
        let normalizedMinutes = (totalSeconds % 3600) / 60
        let normalizedSeconds = totalSeconds % 60
        return (
            String(normalizedHours),
            String(format: "%02d", normalizedMinutes),
            String(format: "%02d", normalizedSeconds)
        )
    }

    private func sanitizedHourString(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? "0" : String(digits.prefix(3))
    }

    private func sanitizedMinuteString(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else {
            return "0"
        }
        let trimmed = String(digits.prefix(2))
        return String(min(Int(trimmed) ?? 0, 59))
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
