import Foundation
import Combine

enum MusicImport {
    static func read(_ url: URL) throws -> Data {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw PlayerFailure("Choose a regular music file")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let limit = Int(CR_MUSIC_MAX_BYTES)
        var data = Data()
        while data.count <= limit {
            let size = min(65536, limit + 1 - data.count)
            guard let chunk = try file.read(upToCount: size), !chunk.isEmpty else { return data }
            data.append(chunk)
        }
        throw PlayerFailure("This file exceeds the 8 MiB import limit")
    }

    static func fromFiles(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, Error>?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { local in
            result = Result { try read(local) }
        }
        if let error { throw error }
        guard let result else { throw PlayerFailure("Files could not open this document") }
        return try result.get()
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var state = PlaybackState()
    @Published private(set) var importing = false
    @Published var message: String?
    private let playback = Playback()
    // Preserve the existing offline slot across upgrades. Its contents identify the format.
    private let saved = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask)[0].appendingPathComponent("current.nsf")

    init() {
        playback.notify = { [weak self] state in
            DispatchQueue.main.async {
                self?.state = state
                self?.message = state.error
            }
        }
        perform { [saved] player in
            if FileManager.default.fileExists(atPath: saved.path) {
                try player.load(MusicImport.read(saved))
            }
        }
    }

    deinit {
        let player = playback
        player.queue.async { player.shutdown() }
    }

    private func perform(_ operation: @escaping (Playback) throws -> Void) {
        let player = playback
        player.queue.async { [weak self] in
            let failure: String?
            do {
                try operation(player)
                failure = nil
            } catch { failure = error.localizedDescription }
            let snapshot = player.state
            DispatchQueue.main.async {
                self?.state = snapshot
                self?.message = failure
            }
        }
    }

    func open(_ url: URL) {
        guard !importing else { return }
        importing = true
        Task {
            defer { importing = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try MusicImport.fromFiles(url)
                }.value
                perform { [saved] in try $0.load(data, saveTo: saved) }
            } catch { message = error.localizedDescription }
        }
    }

    func play() { perform { try $0.play() } }
    func pause() { perform { $0.pause() } }
    func stop() { perform { $0.stop() } }
    func select(_ track: Int) { perform { try $0.select(track) } }
}
