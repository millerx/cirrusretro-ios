import AVFAudio
import MediaPlayer

// Commands and AVAudioSession events run on the same worker as app actions and
// natural track completion. Only the main queue updates the system presentation.
final class SystemMedia {
    enum Command {
        case play, pause, toggle, next, previous

        func enabled(in snapshot: PlayerSnapshot) -> Bool {
            guard snapshot.recording != nil, snapshot.playback.transport != .stopped else { return false }
            switch self {
            case .play: return snapshot.playback.transport == .paused
            case .pause: return snapshot.playback.transport == .playing || snapshot.resumePending
            case .toggle: return true
            case .next: return snapshot.canAdvance
            case .previous: return snapshot.canGoBack
            }
        }

        func run(on player: LibraryPlayer) -> MPRemoteCommandHandlerStatus {
            guard enabled(in: player.snapshot) else { return .noActionableNowPlayingItem }
            let success = player.perform { player in
                switch self {
                case .play: try player.playback.play()
                case .pause: player.playback.pause()
                case .toggle:
                    if player.playback.state.transport == .playing {
                        player.playback.pause()
                    } else {
                        try player.playback.play()
                    }
                case .next: try player.advance()
                case .previous: try player.previous()
                }
            }
            return success ? .success : .commandFailed
        }
    }

    private var targets: [(MPRemoteCommand, Any)] = []
    private var observers: [NSObjectProtocol] = []

    func connect(to player: LibraryPlayer) {
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, Command)] = [
            (center.playCommand, .play), (center.pauseCommand, .pause),
            (center.togglePlayPauseCommand, .toggle), (center.nextTrackCommand, .next),
            (center.previousTrackCommand, .previous)
        ]
        for (remote, command) in commands {
            // Advertise transport support before the nonmixable audio session
            // activates. The handler checks the actual selection on its worker.
            remote.isEnabled = command != .next && command != .previous
            let token = remote.addTarget { [weak player] _ in
                guard let player else { return .commandFailed }
                return player.playback.queue.sync { command.run(on: player) }
            }
            targets.append((remote, token))
        }
        center.changePlaybackPositionCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false

        let notifications = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()
        observers.append(notifications.addObserver(forName: AVAudioSession.interruptionNotification,
                                                   object: audioSession, queue: nil) { [weak player] note in
            guard let player, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            player.playback.queue.async {
                player.perform {
                    switch type {
                    case .began: $0.playback.interruptionBegan()
                    case .ended:
                        let resume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                        try $0.playback.interruptionEnded(shouldResume: resume)
                    @unknown default: break
                    }
                }
            }
        })
        observers.append(notifications.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                   object: audioSession, queue: nil) { [weak player] note in
            guard let player, let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            player.playback.queue.async {
                player.perform { try $0.playback.routeChanged(reason) }
            }
        })
        observers.append(notifications.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                   object: nil, queue: nil) { [weak player] note in
            guard let player, let engine = note.object as? AVAudioEngine else { return }
            player.playback.queue.async {
                guard player.playback.owns(engine) else { return }
                player.perform { try $0.playback.recoverConfiguration() }
            }
        })
    }

    deinit {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        for (remote, token) in targets { remote.removeTarget(token) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    static func info(for snapshot: PlayerSnapshot) -> [String: Any]? {
        let state = snapshot.playback
        guard let recording = snapshot.recording, state.transport != .stopped else { return nil }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.count > 1 ? "\(recording.title) · Track \(state.track + 1)" : recording.title,
            MPMediaItemPropertyAlbumTrackNumber: state.track + 1,
            MPMediaItemPropertyAlbumTrackCount: state.count,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state.transport == .playing ? 1.0 : 0.0
        ]
        if !state.artist.isEmpty { info[MPMediaItemPropertyArtist] = state.artist }
        info[MPMediaItemPropertyPlaybackDuration] = state.duration
        return info
    }

    func update(_ snapshot: PlayerSnapshot) {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = Command.next.enabled(in: snapshot)
        center.previousTrackCommand.isEnabled = Command.previous.enabled(in: snapshot)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = Self.info(for: snapshot)
    }
}
