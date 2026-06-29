import Cocoa

/// Pauses media that is currently playing (browser video, Music, Spotify, etc.)
/// when a break begins.
///
/// macOS only exposes a single play/pause *toggle*, not a dedicated pause, so we
/// first read the now-playing state from the private MediaRemote framework and
/// only act when something is actually playing. This avoids accidentally
/// starting playback when nothing is open.
///
/// Sending the media key requires Accessibility permission.
final class MediaController {
    private typealias MRNowPlayingIsPlaying = @convention(c) (
        DispatchQueue, @escaping (Bool) -> Void
    ) -> Void

    private let isPlayingFunction: MRNowPlayingIsPlaying?

    // NX_KEYTYPE_PLAY (system-defined media key for play/pause toggle).
    private static let playPauseKey: Int32 = 16

    init() {
        isPlayingFunction = MediaController.loadIsPlayingFunction()
    }

    /// Pauses currently-playing media. The completion runs on the main queue and
    /// reports whether a pause command was sent.
    func pauseIfPlaying(completion: ((Bool) -> Void)? = nil) {
        guard let isPlayingFunction else {
            // Can't determine playback state; do nothing rather than risk
            // toggling playback on.
            completion?(false)
            return
        }

        isPlayingFunction(DispatchQueue.main) { [weak self] isPlaying in
            guard let self, isPlaying else {
                completion?(false)
                return
            }
            self.sendPlayPauseKey()
            completion?(true)
        }
    }

    private func sendPlayPauseKey() {
        postMediaKeyEvent(keyDown: true)
        postMediaKeyEvent(keyDown: false)
    }

    private func postMediaKeyEvent(keyDown: Bool) {
        let flagsValue = keyDown ? 0xA00 : 0xB00
        let data1 = Int((Self.playPauseKey << 16) | Int32(flagsValue))

        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flagsValue)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    private static func loadIsPlayingFunction() -> MRNowPlayingIsPlaying? {
        guard
            let handle = dlopen(
                "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
                RTLD_NOW
            ),
            let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        else {
            return nil
        }
        return unsafeBitCast(symbol, to: MRNowPlayingIsPlaying.self)
    }
}
