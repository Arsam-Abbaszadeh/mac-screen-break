import AppKit
import SwiftUI

struct EmergencyExitChallenge {
    let prompts: [String]
}

struct EmergencyExitView: View {
    let challenge: EmergencyExitChallenge
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPromptIndex = 0
    @State private var typedText = ""
    @State private var statusMessage = "Type the exact string shown below. Paste is disabled."
    @State private var confirmAvailableAt = Date.distantFuture
    @State private var readyToFinish = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Emergency Exit")
                .font(.title2.weight(.semibold))

            Text("This flow is intentionally inconvenient. For a true emergency, use macOS force quit.")
                .foregroundStyle(.secondary)

            Text("String \(currentPromptIndex + 1) of \(challenge.prompts.count)")
                .font(.headline)

            Text("Type this exact string:")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(currentPrompt)
                .font(.system(.body, design: .monospaced))
                .textSelection(.disabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            PasteBlockingTextField(text: $typedText)
                .frame(height: 30)
                .overlay(alignment: .leading) {
                    if typedText.isEmpty {
                        Text("Type the string exactly as shown")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: typedText) { newValue in
                    handleTypedText(newValue)
                }

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(readyToFinish ? .green : .secondary)

            HStack {
                Button("Close") {
                    dismiss()
                }

                Spacer()

                Button(readyToFinish ? "Exit Lockdown" : confirmButtonTitle) {
                    onSuccess()
                }
                .disabled(!readyToFinish)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { now in
            if !readyToFinish && now >= confirmAvailableAt && confirmAvailableAt != .distantFuture {
                readyToFinish = true
                statusMessage = "Final delay complete. You may exit lockdown now."
            }
        }
    }

    private var currentPrompt: String {
        challenge.prompts[currentPromptIndex]
    }

    private var confirmButtonTitle: String {
        let remaining = max(0, Int(confirmAvailableAt.timeIntervalSinceNow.rounded(.up)))
        return remaining > 0 ? "Wait \(remaining)s" : "Exit Lockdown"
    }

    private func handleTypedText(_ value: String) {
        if value == currentPrompt {
            if currentPromptIndex == challenge.prompts.count - 1 {
                typedText = ""
                confirmAvailableAt = Date().addingTimeInterval(10)
                statusMessage = "Challenge complete. Wait 10 seconds for the final confirmation."
            } else {
                currentPromptIndex += 1
                typedText = ""
                statusMessage = "Correct. Continue with the next string."
            }
            return
        }

        if !currentPrompt.hasPrefix(value) {
            typedText = ""
            statusMessage = "Mismatch. Start that string again from the beginning."
        } else {
            statusMessage = "Keep going. Match every character exactly."
        }
    }
}

struct PasteBlockingTextField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> PasteBlockingNSTextField {
        let view = PasteBlockingNSTextField()
        view.delegate = context.coordinator
        view.isBordered = true
        view.focusRingType = .none
        return view
    }

    func updateNSView(_ nsView: PasteBlockingNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else {
                return
            }
            text = field.stringValue
        }
    }
}

final class PasteBlockingNSTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            NSSound.beep()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }
}
