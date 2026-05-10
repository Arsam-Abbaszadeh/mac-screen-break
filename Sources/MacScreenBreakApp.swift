import AppKit
import SwiftUI

@main
struct MacScreenBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sessionController = SessionController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionController)
                .onAppear {
                    appDelegate.sessionController = sessionController
                }
                .frame(minWidth: 360, idealWidth: 400, minHeight: 300, idealHeight: 320)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Mac Screen Break") {
                    sessionController.handleQuitRequest()
                }
                .keyboardShortcut("q")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var sessionController: SessionController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        sessionController?.reassertLockdownWindowsIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        sessionController?.applicationShouldTerminate() ?? .terminateNow
    }
}
