import AVFAudio
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
            XCTAssertEqual(player.remaining, Int(CR_MUSIC_MAX_TRACK_FRAMES - CR_BLOCK_FRAMES))
            player.stop()
            XCTAssertEqual(player.state.transport, .stopped)
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
