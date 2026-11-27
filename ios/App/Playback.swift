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
    var error: String?
}

// Accessed exclusively on the player's serial queue, including timer events
// and shutdown. GCD can move that queue between physical threads.
final class Playback {
    let queue = DispatchQueue(label: "CirrusRetro.playback", qos: .userInitiated)
    private(set) var state = PlaybackState()
    private var handle: OpaquePointer?
    private var output: CRAudioOutput?
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
    func load(_ data: Data, saveTo url: URL? = nil, track: Int? = nil) throws {
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
        shutdown()
        frameLimit = Int(info.frame_limit)
        handle = candidate
        adopted = true
        state = PlaybackState(title: metadata.title, artist: metadata.artist,
                              copyright: metadata.copyright, track: selectedTrack,
                              count: metadata.trackCount)
    }

    private func releaseOutput() {
        timer?.cancel()
        timer = nil
        if let output {
            output.engine.stop()
            self.output = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        state.transport = .stopped
    }

    func stop() { releaseOutput() }

    func shutdown() {
        releaseOutput()
        cr_music_close(handle)
        handle = nil
        state = PlaybackState()
    }

    func pause() {
        guard state.transport == .playing else { return }
        timer?.cancel()
        timer = nil
        output?.engine.pause()
        state.transport = .paused
    }

    func select(_ track: Int) throws {
        guard (0..<state.count).contains(track) else { throw PlayerFailure("Invalid track") }
        let restart = state.transport == .playing
        stop()
        state.track = track
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
        guard state.transport != .playing else { return }
        state.error = nil
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
            try audio.engine.start()
            state.transport = .playing
            let clock = DispatchSource.makeTimerSource(queue: queue)
            clock.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            clock.setEventHandler { [weak self] in self?.tick() }
            timer = clock
            clock.resume()
        } catch {
            stop()
            throw error
        }
    }

    private func tick() {
        guard state.transport == .playing, let output else { return }
        do {
            if remaining == 0 && output.freeFrames == Int(CR_QUEUE_FRAMES) {
                stop()
            } else if !output.engine.isRunning {
                throw PlayerFailure("Audio output stopped. Press Play to restart.")
            } else {
                try produce(into: output)
                return
            }
        } catch {
            stop()
            state.error = error.localizedDescription
        }
        notify?(state)
    }
}
