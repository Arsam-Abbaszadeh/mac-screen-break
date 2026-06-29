import Cocoa
import ApplicationServices

/// Takes apps out of full-screen modes so the lockdown overlay can cover every
/// display.
///
/// Native full-screen apps occupy dedicated Spaces. Browser/player video
/// full-screen often is not represented as `AXFullScreen`, so the controller
/// combines an Escape key press for the focused app with Accessibility updates
/// for native full-screen windows.
///
/// This requires Accessibility permission.
final class FullScreenController {
    private let fullScreenAttribute = "AXFullScreen" as CFString
    private let escapeKeyCode = CGKeyCode(53)

    /// Exits the common full-screen modes that can prevent the overlay from
    /// being visible. Returns true when the caller should wait for a Space or
    /// full-screen animation to settle.
    @discardableResult
    func prepareForOverlay() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let sentEscape = sendEscapeToFrontmostApp()
        let exitedNativeFullScreen = exitAllFullScreenWindows()
        return sentEscape || exitedNativeFullScreen
    }

    /// Exits full-screen for every window of every regular app across all
    /// displays. Returns true if at least one window was taken out of
    /// full-screen (useful for deciding whether to wait for the exit animation).
    @discardableResult
    func exitAllFullScreenWindows() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        var didExitAny = false
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else {
                continue
            }
            let pid = app.processIdentifier
            guard pid > 0 else {
                continue
            }

            let axApp = AXUIElementCreateApplication(pid)
            var windowsValue: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
            guard status == .success, let windows = windowsValue as? [AXUIElement] else {
                continue
            }

            for window in windows where exitFullScreen(window: window) {
                didExitAny = true
            }
        }

        return didExitAny
    }

    @discardableResult
    func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func exitFullScreen(window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let copyStatus = AXUIElementCopyAttributeValue(window, fullScreenAttribute, &value)
        guard
            copyStatus == .success,
            let cfValue = value,
            CFGetTypeID(cfValue) == CFBooleanGetTypeID(),
            CFBooleanGetValue((cfValue as! CFBoolean))
        else {
            return false
        }

        var isSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, fullScreenAttribute, &isSettable)
        guard isSettable.boolValue else {
            return false
        }

        return AXUIElementSetAttributeValue(window, fullScreenAttribute, kCFBooleanFalse) == .success
    }

    private func sendEscapeToFrontmostApp() -> Bool {
        guard
            let frontmostApp = NSWorkspace.shared.frontmostApplication,
            frontmostApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            frontmostApp.activationPolicy == .regular,
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: false)
        else {
            return false
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
