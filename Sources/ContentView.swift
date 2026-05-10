import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionController: SessionController
    @FocusState private var focusedField: DurationField?

    private enum DurationField: Hashable {
        case startMinutes
        case startSeconds
        case lockdownMinutes
        case lockdownSeconds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Screen Break")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                durationRow(
                    title: "Start lockdown after",
                    minutes: $sessionController.startAfterMinutesText,
                    seconds: $sessionController.startAfterSecondsText,
                    disabled: sessionController.state == .lockdown,
                    minuteField: .startMinutes,
                    secondField: .startSeconds
                )
                durationRow(
                    title: "Lockdown length",
                    minutes: $sessionController.lockdownMinutesText,
                    seconds: $sessionController.lockdownSecondsText,
                    disabled: sessionController.state == .lockdown,
                    minuteField: .lockdownMinutes,
                    secondField: .lockdownSeconds
                )

                Toggle("Mute all sound during lockdown", isOn: $sessionController.muteAudio)
                    .disabled(sessionController.state == .lockdown)
            }

            Text(sessionController.remainingCountdownText())
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            if let quitAttemptMessage = sessionController.quitAttemptMessage {
                Text(quitAttemptMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button(sessionController.state == .armed ? "Restart" : "Start") {
                    sessionController.startSession()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sessionController.state == .lockdown)

                Button("Cancel") {
                    sessionController.cancelSession()
                }
                .disabled(sessionController.state == .idle)
            }
        }
        .padding(24)
        .onChange(of: focusedField) { newValue in
            if newValue == nil {
                sessionController.normalizeTypedDurations()
            }
        }
    }

    private func durationRow(
        title: String,
        minutes: Binding<String>,
        seconds: Binding<String>,
        disabled: Bool,
        minuteField: DurationField,
        secondField: DurationField
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
            Spacer()

            HStack(spacing: 8) {
                durationField(text: minutes, width: 52, placeholder: "00", field: minuteField)
                Text("m")
                    .foregroundStyle(.secondary)
                durationField(text: seconds, width: 40, placeholder: "00", field: secondField)
                Text("s")
                    .foregroundStyle(.secondary)
            }
            .disabled(disabled)
        }
    }

    private func durationField(text: Binding<String>, width: CGFloat, placeholder: String, field: DurationField) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .multilineTextAlignment(.trailing)
            .font(.system(.body, design: .monospaced))
            .focused($focusedField, equals: field)
            .onChange(of: text.wrappedValue) { newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered != newValue {
                    text.wrappedValue = filtered
                }
            }
            .onSubmit {
                sessionController.normalizeTypedDurations()
            }
    }
}
