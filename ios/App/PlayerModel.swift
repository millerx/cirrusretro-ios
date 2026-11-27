import Foundation
import Combine

struct QueuedTrack: Identifiable {
    let id = UUID()
    let recording: Recording
    let track: Int
}

private struct QueueSkip: LocalizedError {
    let errorDescription: String?
    let advanced: Bool
}

struct PlayerSnapshot {
    var playback = PlaybackState()
    var recording: Recording?
    var upcoming: [QueuedTrack] = []
    var message: String?
    var hasPrevious = false
    var resumePending = false

    var canAdvance: Bool { !upcoming.isEmpty || playback.track + 1 < playback.count }
    var canGoBack: Bool { hasPrevious || playback.track > 0 }

    func isPlaying(recordingID: Recording.ID, track: Int) -> Bool {
        playback.transport == .playing && recording?.id == recordingID && playback.track == track
    }
}

// Selection, queue mutations and automatic progression share the playback
// worker. The audio callback continues to consume only the PCM ring.
final class LibraryPlayer {
    let playback = Playback()
    private(set) var recording: Recording?
    private(set) var upcoming: [QueuedTrack] = []
    private var history: [QueuedTrack] = []
    var snapshot: PlayerSnapshot {
        PlayerSnapshot(playback: playback.state, recording: recording, upcoming: upcoming,
                       hasPrevious: !history.isEmpty, resumePending: playback.resumeAfterInterruption)
    }

    var publish: ((PlayerSnapshot) -> Void)?

    init() {
        playback.notify = { [weak self] state in
            self?.perform {
                if let error = state.error { throw PlayerFailure(error) }
                try $0.next()
            }
        }
    }

    @discardableResult
    func perform(_ action: (LibraryPlayer) throws -> Void) -> Bool {
        var message: String?
        var success = true
        do {
            try action(self)
        } catch let warning as QueueSkip {
            message = warning.errorDescription
            success = warning.advanced
        } catch {
            message = error.localizedDescription
            success = false
        }
        var result = snapshot
        result.message = message
        publish?(result)
        return success
    }

    func prepare(_ item: Recording, track: Int? = nil, continuingSession: Bool = false) throws {
        let data = try item.readForPlayback()
        try playback.load(data, track: track, continuingSession: continuingSession)
        recording = item
    }

    func play(_ item: Recording, track: Int) throws {
        let previous = playback.hasPlayedSelection ? currentTrack : nil
        try start(item, track: track)
        if let previous { history.append(previous) }
    }

    private var currentTrack: QueuedTrack? {
        recording.map { QueuedTrack(recording: $0, track: playback.state.track) }
    }

    private func start(_ item: Recording, track: Int) throws {
        try prepare(item, track: track, continuingSession: true)
        try playback.play()
    }

    func enqueue(_ item: Recording, track: Int) {
        upcoming.append(QueuedTrack(recording: item, track: track))
    }

    func dequeue(_ id: QueuedTrack.ID) {
        upcoming.removeAll { $0.id == id }
    }

    func remove(_ item: Recording) {
        history.removeAll { $0.recording.id == item.id }
        upcoming.removeAll { $0.recording.id == item.id }
        if recording?.id == item.id {
            playback.shutdown()
            recording = nil
        }
    }

    func next() throws {
        let previous = playback.hasPlayedSelection ? currentTrack : nil
        var advanced = false
        var firstFailure: String?
        var skipped = 0
        while !upcoming.isEmpty {
            let item = upcoming.removeFirst()
            guard let error = try startQueuedTrack(item) else {
                advanced = true
                if let previous { history.append(previous) }
                break
            }
            skipped += 1
            if firstFailure == nil {
                firstFailure = "\(item.recording.title) — \(error.localizedDescription)"
            }
        }
        if let firstFailure {
            throw QueueSkip(errorDescription: "Skipped \(skipped) queued item(s). \(firstFailure)", advanced: advanced)
        }
    }

    private func startQueuedTrack(_ item: QueuedTrack) throws -> Error? {
        do {
            try prepare(item.recording, track: item.track, continuingSession: true)
        } catch {
            return error
        }
        do {
            try playback.play()
        } catch let error as PlaybackEmulationFailure {
            return error
        }
        // Audio session or engine errors propagate so the selected track can be retried.
        return nil
    }

    func advance() throws {
        if !upcoming.isEmpty {
            try next()
        } else if let recording, playback.state.track + 1 < playback.state.count {
            try play(recording, track: playback.state.track + 1)
        }
    }

    func previous() throws {
        guard let current = currentTrack else { return }
        if let last = history.last {
            try start(last.recording, track: last.track)
            history.removeLast()
        } else if current.track > 0 {
            try start(current.recording, track: current.track - 1)
        } else {
            return
        }
        upcoming.insert(current, at: 0)
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var player = PlayerSnapshot()
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var busy = true
    @Published private(set) var importing = false
    @Published var libraryMessage: String?

    private let session = LibraryPlayer()
    private let media: SystemMedia
    private let library: MusicLibrary
    private let libraryQueue = DispatchQueue(label: "CirrusRetro.library", qos: .userInitiated)

    init(applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                             in: .userDomainMask)[0]) {
        library = MusicLibrary(applicationSupport: applicationSupport)
        media = SystemMedia()
        session.publish = { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self else { return }
                self.player = snapshot
                self.media.update(snapshot)
            }
        }
        media.connect(to: session)
        updateLibrary { library in
            do {
                let legacy = try library.migrateLegacy()
                return (legacy, nil)
            } catch {
                return (nil, "Previous import — \(error.localizedDescription)")
            }
        }
    }

    deinit {
        let session = session
        session.playback.queue.async { session.playback.shutdown() }
    }

    // Storage edits are serialized and published together with a fresh catalog.
    // File coordination and emulator validation on import stay off the audio worker.
    private func updateLibrary(
        _ edit: @escaping (MusicLibrary) throws -> (preferred: Recording?, message: String?),
        removed: Recording? = nil
    ) {
        let library = library
        busy = true
        libraryQueue.async { [weak self] in
            var preferred: Recording?
            var message: String?
            var removedItem: Recording?
            do {
                (preferred, message) = try edit(library)
                removedItem = removed
            } catch {
                message = error.localizedDescription
            }

            let contents = Result { try library.contents() }
            DispatchQueue.main.async { [weak self, preferred, message, removedItem] in
                guard let self else { return }
                var notices = [message].compactMap { $0 }
                switch contents {
                case .success(let contents):
                    self.recordings = contents.recordings
                    if contents.unreadableEntries > 0 {
                        notices.append("Some library metadata could not be read.")
                    }
                    let first = preferred ?? contents.recordings.first(where: \.available)
                    self.perform { session in
                        if let removedItem { session.remove(removedItem) }
                        if removedItem == nil, session.recording == nil, let first {
                            try session.prepare(first)
                        }
                    }
                case .failure(let error):
                    notices.append(error.localizedDescription)
                    if let removedItem {
                        self.recordings.removeAll { $0.id == removedItem.id }
                        self.perform { $0.remove(removedItem) }
                    }
                }
                self.libraryMessage = notices.isEmpty ? nil : notices.joined(separator: "\n")
                self.importing = false
                self.busy = false
            }
        }
    }

    func open(_ urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        importing = true
        updateLibrary { library in
            var first: Recording?
            var added = 0, duplicates = 0, failed = 0
            var firstError: String?
            for url in urls {
                do {
                    let result = try library.add(MusicImport.fromFiles(url), fileName: url.lastPathComponent)
                    if first == nil { first = result.recording }
                    if result.added { added += 1 } else { duplicates += 1 }
                } catch {
                    failed += 1
                    if firstError == nil { firstError = "\(url.lastPathComponent) — \(error.localizedDescription)" }
                }
            }
            var summary: String?
            if duplicates > 0 || failed > 0 {
                summary = "Imported \(added) · Already in Library \(duplicates) · Failed \(failed)"
                if let firstError { summary = "\(summary ?? "")\n\(firstError)" }
            }
            return (first, summary)
        }
    }

    func remove(_ item: Recording) {
        guard !busy else { return }
        updateLibrary({ library in
            try library.remove(item)
            return (nil, nil)
        }, removed: item)
    }

    private func perform(_ action: @escaping (LibraryPlayer) throws -> Void) {
        let session = session
        session.playback.queue.async { session.perform(action) }
    }

    func play(_ item: Recording, track: Int) { perform { try $0.play(item, track: track) } }
    func enqueue(_ item: Recording, track: Int) { perform { $0.enqueue(item, track: track) } }
    func dequeue(_ id: QueuedTrack.ID) { perform { $0.dequeue(id) } }
    func next() { perform { try $0.next() } }
    func play() { perform { try $0.playback.play() } }
    func pause() { perform { $0.playback.pause() } }
    func stop() { perform { $0.playback.stop() } }
    func select(_ track: Int) { perform { try $0.playback.select(track) } }
}
