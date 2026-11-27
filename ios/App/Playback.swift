import AVFAudio
import Foundation

struct PlayerFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct PlaybackEmulationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func check(_ error: UnsafePointer<CChar>?) throws {
    if let error { throw PlaybackEmulationFailure(message: String(cString: error)) }
}

struct PlaybackState {
    enum Transport: String { case stopped = "Stopped", playing = "Playing", paused = "Paused" }
    var title = "", artist = "", copyright = ""
    var track = 0, count = 0
    var transport = Transport.stopped
    var duration: TimeInterval?
    var elapsed: TimeInterval = 0
    var error: String?
}

// Accessed exclusively on the player's serial queue, including timer events
// and shutdown. GCD can move that queue between physical threads.
final class Playback {
    let queue = DispatchQueue(label: "CirrusRetro.playback", qos: .userInitiated)
    private var transportState = PlaybackState()
    var state: PlaybackState {
        var snapshot = transportState
        if let output {
            let buffered = Int(CR_QUEUE_FRAMES) - Int(output.freeFrames)
            snapshot.elapsed = Double(max(0, frameLimit - remaining - buffered)) / Double(CR_MUSIC_RATE)
        }
        return snapshot
    }
    private var handle: OpaquePointer?
    private var output: CRAudioOutput?
    private(set) var hasPlayedSelection = false
    private var playedThroughExternalOutput = false
    private var sessionActive = false
    private(set) var resumeAfterInterruption = false
    private var engineStoppedSince: DispatchTime?
    private var timer: DispatchSourceTimer?
    private var pcm = [Int16](repeating: 0, count: Int(CR_BLOCK_FRAMES * CR_MUSIC_CHANNELS))
    private var frameLimit = 0
    private(set) var remaining = 0
    var notify: ((PlaybackState) -> Void)?

    private static func open(_ data: Data) throws -> OpaquePointer {
        var candidate: OpaquePointer?
        try data.withUnsafeBytes {
            try check(cr_music_open($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &candidate))
        }
        guard let candidate else { throw PlayerFailure("Music could not be opened") }
        return candidate
    }

    static func inspect(_ data: Data) throws -> MusicMetadata {
        let candidate = try open(data)
        defer { cr_music_close(candidate) }
        var info = cr_music_info()
        try check(cr_music_get_info(candidate, &info))
        try check(cr_music_select(candidate, info.default_track))
        return try MusicMetadata(info)
    }

    // Preserve the current selection/output if a replacement fails validation or saving.
    func load(_ data: Data, saveTo url: URL? = nil, track: Int? = nil,
              continuingSession: Bool = false) throws {
        let candidate = try Self.open(data)
        var adopted = false
        defer { if !adopted { cr_music_close(candidate) } }
        var info = cr_music_info()
        try check(cr_music_get_info(candidate, &info))
        let metadata = try MusicMetadata(info)
        let selectedTrack = track ?? metadata.defaultTrack
        guard (0..<metadata.trackCount).contains(selectedTrack) else { throw PlayerFailure("Invalid track") }
        try check(cr_music_select(candidate, UInt32(selectedTrack)))
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        releaseOutput(deactivate: !continuingSession)
        cr_music_close(handle)
        frameLimit = Int(info.frame_limit)
        handle = candidate
        hasPlayedSelection = false
        adopted = true
        transportState = PlaybackState(title: metadata.title, artist: metadata.artist,
                              copyright: metadata.copyright, track: selectedTrack,
                              count: metadata.trackCount,
                              duration: frameLimit < Int(CR_MUSIC_MAX_TRACK_FRAMES)
                                ? Double(frameLimit) / Double(CR_MUSIC_RATE) : nil)
    }

    private func deactivateIfIdle() {
        guard output == nil, sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    private func releaseOutput(deactivate: Bool = true) {
        resumeAfterInterruption = false
        engineStoppedSince = nil
        timer?.cancel()
        timer = nil
        if let output {
            output.engine.stop()
            self.output = nil
        }
        if deactivate { deactivateIfIdle() }
        transportState.transport = .stopped
    }

    func stop() { releaseOutput() }

    func shutdown() {
        releaseOutput()
        cr_music_close(handle)
        handle = nil
        transportState = PlaybackState()
    }

    func interruptionBegan() {
        if transportState.transport == .playing {
            pause()
            resumeAfterInterruption = true
        }
        sessionActive = false
    }

    func interruptionEnded(shouldResume: Bool) throws {
        let resume = shouldResume && resumeAfterInterruption
        resumeAfterInterruption = false
        if resume { try play() }
    }

    // AVAudioEngine retains the source-to-mixer format across hardware changes.
    // Restart the current graph only if the system stopped this exact output.
    func owns(_ engine: AVAudioEngine) -> Bool { output?.engine === engine }

    private var externalOutput: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
        }
    }

    func routeChanged(_ reason: AVAudioSession.RouteChangeReason) throws {
        switch reason {
        case .oldDeviceUnavailable, .noSuitableRouteForCategory: pause()
        case .newDeviceAvailable, .routeConfigurationChange, .override: try recoverConfiguration()
        default: break
        }
    }

    func recoverConfiguration() throws {
        guard transportState.transport == .playing, let output else { return }
        // A configuration notification can precede the route-loss notification.
        // Do not restart the graph on the speaker after headphones disappear.
        let external = externalOutput
        if playedThroughExternalOutput && !external {
            pause()
            return
        }
        playedThroughExternalOutput = external
        guard !output.engine.isRunning else { return }
        // A pending interruption may prevent restart. Its notification or the
        // stopped-engine timeout will pause the producer and publish the result.
        try output.engine.start()
        engineStoppedSince = nil
    }

    func pause() {
        resumeAfterInterruption = false
        engineStoppedSince = nil
        guard transportState.transport == .playing else { return }
        timer?.cancel()
        timer = nil
        output?.engine.pause()
        transportState.transport = .paused
    }

    func select(_ track: Int) throws {
        guard (0..<state.count).contains(track) else { throw PlayerFailure("Invalid track") }
        let restart = transportState.transport == .playing
        releaseOutput(deactivate: !restart)
        hasPlayedSelection = false
        transportState.track = track
        if restart { try play() }
    }

    private func produce(into output: CRAudioOutput) throws {
        let frames = min(Int(CR_BLOCK_FRAMES), remaining)
        guard frames > 0, output.freeFrames >= frames else { return }
        try check(cr_music_render(handle, &pcm, frames))
        pcm.withUnsafeBufferPointer { output.write($0.baseAddress!, frames: UInt32(frames)) }
        remaining -= frames
    }

    func play() throws {
        guard handle != nil else { throw PlayerFailure("Import an NSF, SPC or VGM first") }
        guard transportState.transport != .playing else { return }
        resumeAfterInterruption = false
        transportState.error = nil
        do {
            let audio: CRAudioOutput
            if let output {
                audio = output // Resume with buffered frames and guest position intact.
            } else {
                try check(cr_music_select(handle, UInt32(state.track)))
                remaining = frameLimit
                audio = CRAudioOutput()
                output = audio
                try produce(into: audio)
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            sessionActive = true
            try audio.engine.start()
            playedThroughExternalOutput = externalOutput
            hasPlayedSelection = true
            transportState.transport = .playing
            let clock = DispatchSource.makeTimerSource(queue: queue)
            clock.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            clock.setEventHandler { [weak self] in self?.tick() }
            timer = clock
            clock.resume()
        } catch {
            if transportState.transport != .paused { stop() }
            throw error
        }
    }

    private func tick() {
        guard transportState.transport == .playing, let output else { return }
        do {
            if !output.engine.isRunning {
                // Route/configuration and interruption notifications arrive asynchronously.
                // Give them time to identify the cause before reporting a stalled engine.
                let now = DispatchTime.now()
                if engineStoppedSince == nil { engineStoppedSince = now }
                guard let since = engineStoppedSince, now >= since + .seconds(1) else { return }
                pause()
                transportState.error = "Audio output paused. Press Play to resume."
            } else if remaining == 0 && output.freeFrames == Int(CR_QUEUE_FRAMES) {
                releaseOutput(deactivate: false)
            } else {
                engineStoppedSince = nil
                try produce(into: output)
                return
            }
        } catch {
            stop()
            transportState.error = error.localizedDescription
        }
        notify?(state)
        deactivateIfIdle()
    }
}
