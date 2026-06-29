import AppKit
import SwiftUI

@MainActor
final class OverlayWindowManager {
    private var windowsByScreen: [ObjectIdentifier: NSWindow] = [:]
    private weak var sessionController: SessionController?
    private var endDate: Date?

    func presentLockdown(sessionController: SessionController, endDate: Date) {
        self.sessionController = sessionController
        self.endDate = endDate

        let screens = NSScreen.screens
        var nextWindows: [ObjectIdentifier: NSWindow] = [:]

        for screen in screens {
            let key = ObjectIdentifier(screen)
            let window = windowsByScreen[key] ?? makeWindow(for: screen)
            configure(window: window, for: screen, endDate: endDate, sessionController: sessionController)
            nextWindows[key] = window
        }

        for (key, window) in windowsByScreen where nextWindows[key] == nil {
            window.orderOut(nil)
        }

        windowsByScreen = nextWindows
    }

    func update(endDate: Date) {
        guard let sessionController else {
            return
        }

        self.endDate = endDate
        for screen in NSScreen.screens {
            let key = ObjectIdentifier(screen)
            guard let window = windowsByScreen[key] else {
                continue
            }

            configure(window: window, for: screen, endDate: endDate, sessionController: sessionController)
        }
    }

    func dismissAll() {
        for window in windowsByScreen.values {
            window.orderOut(nil)
        }
        windowsByScreen.removeAll()
        sessionController = nil
        endDate = nil
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = LockdownPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = true
        window.backgroundColor = .black
        // Use the shielding window level so the overlay sits above native
        // full-screen apps and full-screen video (which sit above .screenSaver).
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.tabbingMode = .disallowed
        return window
    }

    private func configure(window: NSWindow, for screen: NSScreen, endDate: Date, sessionController: SessionController) {
        window.setFrame(screen.frame, display: true)
        window.contentView = NSHostingView(
            rootView: LockdownOverlayView(
                endDate: endDate,
                message: sessionController.activeSession?.overlayMessage ?? sessionController.overlayMessage
            )
                .environmentObject(sessionController)
        )
        window.orderFrontRegardless()
    }
}

private final class LockdownPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
