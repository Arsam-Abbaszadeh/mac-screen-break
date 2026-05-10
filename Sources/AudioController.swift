import AudioToolbox

final class AudioController {
    private var previousMuteState: UInt32?

    func muteSystemAudio() {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard deviceStatus == noErr else {
            return
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable = DarwinBoolean(false)
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &muteAddress, &isSettable)
        guard settableStatus == noErr, isSettable.boolValue else {
            return
        }

        var currentMute = UInt32(0)
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        let readStatus = AudioObjectGetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            &propertySize,
            &currentMute
        )
        guard readStatus == noErr else {
            return
        }

        previousMuteState = currentMute
        var muted: UInt32 = 1
        AudioObjectSetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &muted
        )
    }

    func restoreSystemAudioIfNeeded() {
        guard let previousMuteState else {
            return
        }

        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard deviceStatus == noErr else {
            self.previousMuteState = nil
            return
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var restoredState = previousMuteState
        AudioObjectSetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &restoredState
        )

        self.previousMuteState = nil
    }
}
