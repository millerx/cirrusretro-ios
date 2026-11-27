import Foundation
import CryptoKit

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

struct MusicMetadata: Codable {
    enum Format: String, Codable {
        case nsf = "NSF", spc = "SPC", vgm = "VGM"
    }

    let format: Format
    let title: String
    let artist: String
    let copyright: String
    let trackCount: Int
    let defaultTrack: Int

    init(_ info: cr_music_info) throws {
        switch info.format {
        case CR_FORMAT_NSF: format = .nsf
        case CR_FORMAT_SPC: format = .spc
        case CR_FORMAT_VGM: format = .vgm
        default: throw PlayerFailure("Unsupported music format")
        }
        title = Self.label(info.title)
        artist = Self.label(info.artist)
        copyright = Self.label(info.copyright)
        trackCount = Int(info.track_count)
        defaultTrack = Int(info.default_track)
    }

    private static func label<T>(_ field: T) -> String {
        withUnsafeBytes(of: field) { bytes in
            let text = Data(bytes.prefix(while: { $0 != 0 }))
            return (String(data: text, encoding: .utf8)
                    ?? String(data: text, encoding: .isoLatin1) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

struct Recording: Identifiable {
    let id: String
    let fileName: String
    let metadata: MusicMetadata
    let url: URL
    let available: Bool

    var title: String {
        metadata.title.isEmpty ? fileName : metadata.title
    }

    static func contentID(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func readForPlayback() throws -> Data {
        let data = try MusicImport.read(url)
        guard Self.contentID(data) == id else {
            throw PlayerFailure("Library file has changed. Import the original file again to restore playback.")
        }
        return data
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [title, metadata.artist, metadata.copyright, fileName, metadata.format.rawValue]
            .contains { $0.localizedStandardContains(query) }
    }
}

// The model serializes all catalog operations on its library queue. Playback
// only reads committed media files and opens its own emulator handle.
struct MusicLibrary {
    private struct Entry: Codable {
        let fileName: String
        let metadata: MusicMetadata
    }

    struct Contents {
        var recordings: [Recording] = []
        var unreadableEntries = 0
    }

    private let root: URL
    private let legacy: URL
    private let files = FileManager.default

    init(applicationSupport: URL) {
        root = applicationSupport.appendingPathComponent("MusicLibrary", isDirectory: true)
        legacy = applicationSupport.appendingPathComponent("current.nsf")
    }

    func contents() throws -> Contents {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                    options: .skipsHiddenFiles)
        var result = Contents()
        for folder in folders {
            do {
                let entry = try readEntry(in: folder)
                result.recordings.append(recording(entry, in: folder))
            } catch {
                result.unreadableEntries += 1
            }
        }
        result.recordings.sort {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return result
    }

    func migrateLegacy() throws -> Recording? {
        guard files.fileExists(atPath: legacy.path) else { return nil }
        let data = try MusicImport.read(legacy)
        return try install(data, fileName: nil, moving: legacy).recording
    }

    func add(_ data: Data, fileName: String) throws -> (recording: Recording, added: Bool) {
        try install(data, fileName: fileName, moving: nil)
    }

    func remove(_ recording: Recording) throws {
        let folder = recording.url.deletingLastPathComponent()
        do {
            try files.removeItem(at: folder)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileNoSuchFileError {
            // An already missing entry counts as removed.
        }
    }

    private func install(_ data: Data, fileName: String?, moving source: URL?) throws
        -> (recording: Recording, added: Bool) {
        let id = Recording.contentID(data)
        let folder = root.appendingPathComponent(id, isDirectory: true)
        let media = folder.appendingPathComponent("music")
        let previous = try? readEntry(in: folder)
        if let entry = previous,
           (try? MusicImport.read(media)) == data {
            if let source { try files.removeItem(at: source) }
            return (recording(entry, in: folder), false)
        }

        let metadata = try Playback.inspect(data)
        let entry = Entry(fileName: previous?.fileName ?? fileName ?? "current.\(metadata.format.rawValue.lowercased())",
                          metadata: metadata)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: entryURL(in: folder), options: .atomic)
        if let source, !files.fileExists(atPath: media.path) {
            // Commit by moving the original within Application Support. An
            // interrupted migration can retry while the original still exists.
            try files.moveItem(at: source, to: media)
        } else {
            try data.write(to: media, options: .atomic)
            if let source { try files.removeItem(at: source) }
        }
        return (recording(entry, in: folder), true)
    }

    private func entryURL(in folder: URL) -> URL {
        folder.appendingPathComponent("metadata.json")
    }

    private func readEntry(in folder: URL) throws -> Entry {
        let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: entryURL(in: folder)))
        guard (1...255).contains(entry.metadata.trackCount),
              (0..<entry.metadata.trackCount).contains(entry.metadata.defaultTrack) else {
            throw PlayerFailure("Invalid library track metadata")
        }
        return entry
    }

    private func recording(_ entry: Entry, in folder: URL) -> Recording {
        let url = folder.appendingPathComponent("music")
        let available = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        return Recording(id: folder.lastPathComponent, fileName: entry.fileName,
                         metadata: entry.metadata, url: url, available: available)
    }
}
