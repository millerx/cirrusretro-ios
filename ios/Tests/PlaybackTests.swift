import AVFAudio
import MediaPlayer
import XCTest
@testable import CirrusRetro

final class PlaybackTests: XCTestCase {
    private func fixture(_ name: String = "pulse", ext: String = "nsf") throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext))
        return try MusicImport.read(url)
    }

    func testTransportImportAndRecovery() throws {
        let player = Playback()
        try player.queue.sync {
            defer { player.shutdown() }
            let saved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: saved) }
            let data = try fixture()
            try player.load(data, saveTo: saved)
            XCTAssertEqual(try MusicImport.fromFiles(saved), data)
            XCTAssertEqual(player.state.title, "Pulse pair")
            XCTAssertEqual(player.state.artist, "Cirrus Retro test")
            XCTAssertEqual(player.state.copyright, "Synthetic fixture")
            XCTAssertEqual(player.state.count, 2)
            XCTAssertEqual(player.state.track, 1)
            try player.play()
            XCTAssertEqual(player.state.transport, .playing)
            player.pause()
            XCTAssertEqual(player.state.transport, .paused)
            try player.play()
            try player.select(0)
            XCTAssertEqual(player.state.track, 0)
            XCTAssertEqual(player.state.transport, .playing)
            XCTAssertThrowsError(try player.load(Data([0]), saveTo: saved))
            XCTAssertEqual(try MusicImport.read(saved), data)
            XCTAssertEqual(player.state.transport, .playing)
            player.stop()
            XCTAssertEqual(player.state.transport, .stopped)
            try player.load(fixture("warning"))
            XCTAssertThrowsError(try player.play())
            XCTAssertEqual(player.state.transport, .stopped)
            try player.select(0)
            try player.play()
        }
    }

    func testReplaceSavedMusicAcrossFormats() throws {
        let player = Playback()
        let saved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: saved) }
        try player.queue.sync {
            defer { player.shutdown() }
            for (ext, title) in [("spc", "BRR pulse"), ("vgm", "PSG pulse"), ("nsf", "Pulse pair")] {
                let data = try fixture(ext: ext)
                try player.load(data, saveTo: saved)
                try player.play()
                player.pause()
                XCTAssertThrowsError(try player.load(Data(data.prefix(32)), saveTo: saved))
                XCTAssertEqual(player.state.transport, .paused)
                XCTAssertEqual(try MusicImport.fromFiles(saved), data)
                try player.play()
                player.shutdown()
                try player.load(MusicImport.read(saved))
                XCTAssertEqual(player.state.title, title)
            }
        }
    }

    func testLibraryTrackIndicatorRequiresActivePlayback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MusicLibrary(applicationSupport: root)
        let recording = try library.add(fixture(), fileName: "pulse.nsf").recording
        let other = try library.add(fixture(ext: "spc"), fileName: "pulse.spc").recording
        let track = recording.metadata.defaultTrack
        var snapshot = PlayerSnapshot(recording: recording)
        snapshot.playback.track = track

        XCTAssertFalse(snapshot.isPlaying(recordingID: recording.id, track: track))
        snapshot.playback.transport = .playing
        XCTAssertTrue(snapshot.isPlaying(recordingID: recording.id, track: track))
        XCTAssertFalse(snapshot.isPlaying(recordingID: recording.id, track: 0))
        XCTAssertFalse(snapshot.isPlaying(recordingID: other.id, track: track))
        snapshot.playback.transport = .paused
        XCTAssertFalse(snapshot.isPlaying(recordingID: recording.id, track: track))
        snapshot.playback.transport = .stopped
        XCTAssertFalse(snapshot.isPlaying(recordingID: recording.id, track: track))
    }

    func testLibraryMigratesEachLegacyFormatAndSurvivesReopening() throws {
        for ext in ["nsf", "spc", "vgm"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let legacy = root.appendingPathComponent("current.nsf")
            let data = try fixture(ext: ext)
            try data.write(to: legacy)

            let library = MusicLibrary(applicationSupport: root)
            let entry = try XCTUnwrap(library.migrateLegacy())
            XCTAssertEqual(entry.fileName, "current.\(ext)")
            XCTAssertEqual(entry.metadata.format.rawValue, ext.uppercased())
            XCTAssertTrue(entry.available)
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))

            let reopened = MusicLibrary(applicationSupport: root)
            XCTAssertNil(try reopened.migrateLegacy())
            XCTAssertEqual(try reopened.contents().recordings.map(\.id), [entry.id])
            XCTAssertEqual(try MusicImport.read(entry.url), data)
            XCTAssertEqual(try reopened.add(data, fileName: "renamed.music").recording.id, entry.id)
            XCTAssertFalse(try reopened.add(data, fileName: "renamed.music").added)
            try reopened.remove(entry)
            XCTAssertTrue(try reopened.contents().recordings.isEmpty)
            XCTAssertNil(try reopened.migrateLegacy())
        }
    }

    func testUpgradeReadsExisting032CatalogAndRepairsChangedAudioInPlace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // Frozen 0.3.2 on-disk layout, independent of the current catalog writer.
        let id = "1a1416707d79a7623cbd1c00d982f0fd10ace36fbbd864e960f8eb45f64f5913"
        let folder = root.appendingPathComponent("MusicLibrary").appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metadata = Data(#"{"fileName":"original.nsf","metadata":{"format":"NSF","title":"Pulse pair","artist":"Cirrus Retro test","copyright":"Synthetic fixture","trackCount":2,"defaultTrack":1}}"#.utf8)
        let catalogURL = folder.appendingPathComponent("metadata.json")
        try metadata.write(to: catalogURL)
        let original = try fixture()
        try original.write(to: folder.appendingPathComponent("music"))
        let library = MusicLibrary(applicationSupport: root)
        let item = try XCTUnwrap(library.contents().recordings.first)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.metadata.defaultTrack, 1)
        XCTAssertEqual(try item.readForPlayback(), original)
        XCTAssertFalse(try library.add(original, fileName: "copy.nsf").added)
        XCTAssertEqual(try Data(contentsOf: catalogURL), metadata)

        // A different, playable recording must not be opened under this identity.
        try fixture(ext: "spc").write(to: item.url)
        let player = LibraryPlayer()
        try player.playback.queue.sync {
            defer { player.playback.shutdown() }
            XCTAssertThrowsError(try player.prepare(item))
            XCTAssertNil(player.recording)
            let repaired = try library.add(original, fileName: "backup.nsf").recording
            XCTAssertEqual(repaired.fileName, "original.nsf")
            try player.prepare(repaired)
            XCTAssertEqual(player.recording?.id, id)
        }
        XCTAssertEqual(try library.contents().recordings.count, 1)
    }

    func testLibraryKeepsValidImportsWhenOthersFailAndRepairsMissingMedia() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = MusicLibrary(applicationSupport: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let spc = try fixture(ext: "spc")
        let malformed = Data(spc.prefix(32))
        let legacy = root.appendingPathComponent("current.nsf")
        _ = try library.contents()
        try malformed.write(to: legacy)
        XCTAssertThrowsError(try library.migrateLegacy())
        XCTAssertEqual(try MusicImport.read(legacy), malformed)

        let first = try library.add(fixture(), fileName: "two-tracks.nsf")
        XCTAssertThrowsError(try library.add(malformed, fileName: "invalid.spc"))
        let second = try library.add(spc, fileName: "recording.bin").recording
        _ = try library.add(fixture(ext: "vgm"), fileName: "pulse.vgm")
        XCTAssertTrue(first.added)
        XCTAssertEqual(first.recording.metadata.trackCount, 2)
        XCTAssertEqual(first.recording.metadata.defaultTrack, 1)
        XCTAssertTrue(first.recording.matches("CIRRUS"))
        XCTAssertTrue(first.recording.matches("two-tracks"))
        XCTAssertTrue(second.matches("spc"))
        XCTAssertFalse(second.matches("two-tracks"))
        XCTAssertEqual(try library.contents().recordings.map(\.title), ["BRR pulse", "PSG pulse", "Pulse pair"])

        try FileManager.default.removeItem(at: second.url)
        let missing = try XCTUnwrap(library.contents().recordings.first { $0.id == second.id })
        XCTAssertFalse(missing.available)
        let repaired = try library.add(spc, fileName: "recovered.spc")
        XCTAssertTrue(repaired.added)
        XCTAssertTrue(repaired.recording.available)
        XCTAssertEqual(repaired.recording.id, second.id)
        try FileManager.default.removeItem(at: second.url)
        try library.remove(second)
        XCTAssertEqual(try library.contents().recordings.count, 2)
    }

    func testLibraryQueueSkipsMissingAndUnplayableTracksAndPurgesRemovedRecording() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = MusicLibrary(applicationSupport: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = try library.add(fixture(ext: "spc"), fileName: "missing.spc").recording
        let finite = try library.add(fixture(ext: "vgm"), fileName: "finite.vgm").recording
        let unplayable = try library.add(fixture("warning"), fileName: "warning.nsf").recording
        let next = try library.add(fixture(), fileName: "next.nsf").recording
        try FileManager.default.removeItem(at: missing.url)

        let session = LibraryPlayer()
        let advanced = expectation(description: "finite track advanced to next playable item")
        defer { session.playback.queue.sync { session.playback.shutdown() } }
        try session.playback.queue.sync {
            session.publish = { snapshot in
                guard snapshot.recording?.id == next.id else { return }
                XCTAssertEqual(snapshot.playback.track, 0)
                XCTAssertEqual(snapshot.playback.transport, .playing)
                XCTAssertTrue(snapshot.message?.contains("Skipped 2") == true)
                XCTAssertEqual(snapshot.upcoming.map(\.track), [1])
                advanced.fulfill()
            }
            session.enqueue(missing, track: 0)
            session.enqueue(unplayable, track: 1)
            session.enqueue(next, track: 0)
            session.enqueue(next, track: 1)
            try session.play(finite, track: 0)
        }
        wait(for: [advanced], timeout: 6)
        session.playback.queue.sync {
            session.playback.stop()
            XCTAssertEqual(session.upcoming.count, 1)
            session.remove(next)
            XCTAssertTrue(session.upcoming.isEmpty)
            XCTAssertNil(session.recording)
            XCTAssertEqual(session.playback.state.transport, .stopped)
        }
    }

    func testSystemControlsFollowQueueMetadataAndLibraryIndicator() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MusicLibrary(applicationSupport: root)
        let nsf = try library.add(fixture(), fileName: "pair.nsf").recording
        let vgm = try library.add(fixture(ext: "vgm"), fileName: "finite.vgm").recording
        let player = LibraryPlayer()
        try player.playback.queue.sync {
            defer { player.playback.shutdown() }
            try player.prepare(nsf, track: 0)
            XCTAssertNil(SystemMedia.info(for: player.snapshot))
            try player.playback.play()
            XCTAssertFalse(SystemMedia.Command.previous.enabled(in: player.snapshot))
            XCTAssertEqual(SystemMedia.Command.next.run(on: player), .success)
            XCTAssertTrue(player.snapshot.isPlaying(recordingID: nsf.id, track: 1))
            XCTAssertFalse(SystemMedia.Command.next.enabled(in: player.snapshot))
            var info = try XCTUnwrap(SystemMedia.info(for: player.snapshot))
            XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Pulse pair · Track 2")
            XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, nsf.metadata.artist)
            XCTAssertNil(info[MPMediaItemPropertyPlaybackDuration])

            XCTAssertEqual(SystemMedia.Command.pause.run(on: player), .success)
            XCTAssertFalse(player.snapshot.isPlaying(recordingID: nsf.id, track: 1))
            info = try XCTUnwrap(SystemMedia.info(for: player.snapshot))
            XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
            XCTAssertEqual(SystemMedia.Command.play.run(on: player), .success)
            player.enqueue(vgm, track: 0)
            XCTAssertEqual(SystemMedia.Command.next.run(on: player), .success)
            XCTAssertTrue(player.snapshot.isPlaying(recordingID: vgm.id, track: 0))
            info = try XCTUnwrap(SystemMedia.info(for: player.snapshot))
            XCTAssertGreaterThan(try XCTUnwrap(info[MPMediaItemPropertyPlaybackDuration] as? Double), 0)
            XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)
            XCTAssertEqual(SystemMedia.Command.previous.run(on: player), .success)
            XCTAssertTrue(player.snapshot.isPlaying(recordingID: nsf.id, track: 1))
            XCTAssertEqual(player.upcoming.first?.recording.id, vgm.id)
            player.playback.stop()
            XCTAssertNil(SystemMedia.info(for: player.snapshot))
            XCTAssertFalse(SystemMedia.Command.toggle.enabled(in: player.snapshot))
        }
    }

    func testInterruptionIntentAndRouteLossPreservePausedPosition() throws {
        let player = Playback()
        try player.queue.sync {
            defer { player.shutdown() }
            try player.load(fixture())
            try player.play()
            let remaining = player.remaining
            player.interruptionBegan()
            XCTAssertEqual(player.state.transport, .paused)
            XCTAssertTrue(player.resumeAfterInterruption)
            try player.interruptionEnded(shouldResume: true)
            XCTAssertEqual(player.state.transport, .playing)
            XCTAssertEqual(player.remaining, remaining)

            player.interruptionBegan()
            try player.interruptionEnded(shouldResume: false)
            XCTAssertEqual(player.state.transport, .paused)
            try player.play()
            player.interruptionBegan()
            player.pause()
            try player.interruptionEnded(shouldResume: true)
            XCTAssertEqual(player.state.transport, .paused)

            try player.play()
            player.interruptionBegan()
            try player.routeChanged(.oldDeviceUnavailable)
            try player.interruptionEnded(shouldResume: true)
            try player.routeChanged(.newDeviceAvailable)
            XCTAssertEqual(player.state.transport, .paused)
            XCTAssertEqual(player.remaining, remaining)
            try player.play()
            try player.routeChanged(.newDeviceAvailable)
            XCTAssertEqual(player.state.transport, .playing)
            try player.routeChanged(.oldDeviceUnavailable)
            XCTAssertEqual(player.state.transport, .paused)
            player.stop()
            try player.interruptionEnded(shouldResume: true)
            XCTAssertEqual(player.state.transport, .stopped)
        }
    }

    func testFiniteVGMDrainsAndStops() throws {
        let player = Playback()
        let stopped = expectation(description: "finite VGM reached end")
        defer { player.queue.sync { player.shutdown() } }
        try player.queue.sync {
            player.notify = { state in
                XCTAssertNil(state.error)
                XCTAssertEqual(state.transport, .stopped)
                stopped.fulfill()
            }
            try player.load(fixture(ext: "vgm"))
            try player.play()
        }
        wait(for: [stopped], timeout: 6)
        player.queue.sync { XCTAssertEqual(player.remaining, 0) }
    }

    func testLiveProducerRefillsBeyondRingCapacity() throws {
        let player = Playback()
        defer { player.queue.sync { player.shutdown() } }
        try player.queue.sync {
            try player.load(fixture())
            try player.play()
        }
        let refilled = expectation(description: "producer refilled a consumed ring")
        let probe = DispatchSource.makeTimerSource(queue: player.queue)
        probe.schedule(deadline: .now(), repeating: .milliseconds(20))
        probe.setEventHandler {
            if Int(CR_MUSIC_MAX_TRACK_FRAMES) - player.remaining > Int(CR_QUEUE_FRAMES) {
                probe.cancel()
                refilled.fulfill()
            }
        }
        probe.resume()
        defer { probe.cancel() }
        wait(for: [refilled], timeout: 5)
        try player.queue.sync {
            player.pause()
            let paused = player.remaining
            try player.play()
            XCTAssertEqual(player.remaining, paused)
            try player.select(0)
            XCTAssertEqual(player.remaining, Int(CR_MUSIC_MAX_TRACK_FRAMES - CR_QUEUE_FRAMES))
            player.stop()
            XCTAssertEqual(player.state.transport, .stopped)
        }
    }

    func testLargeAudioPullsBetweenProducerWakes() throws {
        let frames: AVAudioFrameCount = 4096
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        for ext in ["nsf", "spc"] {
            let output = CRAudioOutput()
            let player = Playback { output }
            try player.queue.sync { () throws -> Void in
                defer { player.shutdown() }
                try output.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: frames)
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
                try player.load(fixture(ext: ext))
                try player.play()
                // Holding the serial queue makes the producer cadence deterministic.
                // Alternate single and double pulls before allowing its next wake.
                for wake in 0..<8 {
                    for _ in 0..<(1 + wake % 2) {
                        let before = Int(output.freeFrames)
                        XCTAssertEqual(try output.engine.renderOffline(frames, to: buffer), .success)
                        XCTAssertEqual(buffer.frameLength, frames)
                        XCTAssertEqual(Int(output.freeFrames) - before, Int(frames), "Every frame must come from the ring")
                    }
                    let consumed = Int(output.freeFrames)
                    let previous = player.remaining
                    player.tick()
                    XCTAssertEqual(previous - player.remaining, consumed)
                    XCTAssertEqual(output.freeFrames, 0)
                }
            }
        }
    }

    func testGuestWorkLimitOnARM64() throws {
        var data = try fixture()
        data[110] = 1 // One microsecond NTSC play period.
        data[111] = 0
        var handle: OpaquePointer?
        defer { cr_music_close(handle) }
        let error = data.withUnsafeBytes {
            cr_music_open($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &handle)
        }
        XCTAssertNil(error)
        XCTAssertNil(cr_music_select(handle, 0))
        var pcm = [Int16](repeating: 0, count: Int(CR_BLOCK_FRAMES * CR_MUSIC_CHANNELS))
        let start = DispatchTime.now().uptimeNanoseconds
        XCTAssertNotNil(cr_music_render(handle, &pcm, Int(CR_BLOCK_FRAMES)))
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        print("Guest work-limit rejection in \(Double(elapsed) / 1_000_000) ms")
        XCTAssertLessThan(elapsed, 1_000_000_000)
    }

    func testFileSizeLimit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(count: Int(CR_MUSIC_MAX_BYTES) + 1).write(to: file)
        XCTAssertThrowsError(try MusicImport.read(file))
    }

    func testEmulatorThroughSourceNode() throws {
        let output = CRAudioOutput()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        try output.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try output.engine.start()
        defer { output.engine.stop() }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        let tones: [(String, UInt32, Double)] = [
            ("nsf", 0, 440), ("nsf", 1, 881), ("spc", 0, 500), ("vgm", 0, 499)
        ]
        for (ext, track, pitch) in tones {
            let data = try fixture(ext: ext)
            var music: OpaquePointer?
            let error = data.withUnsafeBytes {
                cr_music_open($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &music)
            }
            XCTAssertNil(error)
            defer { cr_music_close(music) }
            XCTAssertNil(cr_music_select(music, track))
            var crossings = 0
            var previous: Float = 0
            var samples = [Int16](repeating: 0, count: 1024)
            for _ in 0..<86 {
                XCTAssertNil(cr_music_render(music, &samples, 512))
                output.write(samples, frames: 512)
                XCTAssertEqual(try output.engine.renderOffline(512, to: buffer), .success)
                XCTAssertEqual(buffer.frameLength, 512)
                let left = try XCTUnwrap(buffer.floatChannelData)[0]
                for index in 0..<512 {
                    if previous <= 0 && left[index] > 0 { crossings += 1 }
                    previous = left[index]
                }
            }
            XCTAssertEqual(Double(crossings), pitch, accuracy: 15)
        }
        XCTAssertEqual(try output.engine.renderOffline(512, to: buffer), .success)
        let planes = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 {
            XCTAssertTrue((0..<512).allSatisfy { planes[channel][$0] == 0 })
        }
    }
}
