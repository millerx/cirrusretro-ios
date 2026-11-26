import AVFAudio
import XCTest
@testable import CirrusRetro

final class PlaybackTests: XCTestCase {
    private func fixture(_ name: String = "pulse") throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "nsf"))
        return try NSFImport.read(url)
    }

    func testTransportImportAndRecovery() throws {
        let player = Playback()
        try player.queue.sync {
            defer { player.shutdown() }
            let saved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: saved) }
            let data = try fixture()
            try player.load(data, saveTo: saved)
            XCTAssertEqual(try NSFImport.fromFiles(saved), data)
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
            XCTAssertEqual(try NSFImport.read(saved), data)
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
            if Int(CR_NSF_MAX_TRACK_FRAMES) - player.remaining > Int(CR_QUEUE_FRAMES) {
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
            XCTAssertEqual(player.remaining, Int(CR_NSF_MAX_TRACK_FRAMES - CR_BLOCK_FRAMES))
            player.stop()
            XCTAssertEqual(player.state.transport, .stopped)
        }
    }

    func testFileSizeLimit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(count: Int(CR_NSF_MAX_BYTES) + 1).write(to: file)
        XCTAssertThrowsError(try NSFImport.read(file))
    }

    func testEmulatorThroughSourceNode() throws {
        let data = try fixture()
        var nsf: OpaquePointer?
        defer { cr_nsf_close(nsf) }
        let error = data.withUnsafeBytes { cr_nsf_open($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &nsf) }
        XCTAssertNil(error)
        let output = CRAudioOutput()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        try output.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try output.engine.start()
        defer { output.engine.stop() }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        for track in 0..<2 {
            XCTAssertNil(cr_nsf_select(nsf, UInt32(track)))
            var crossings = 0
            var previous: Float = 0
            var samples = [Int16](repeating: 0, count: 1024)
            for _ in 0..<86 {
                XCTAssertNil(cr_nsf_render(nsf, &samples, 512))
                output.write(samples, frames: 512)
                XCTAssertEqual(try output.engine.renderOffline(512, to: buffer), .success)
                XCTAssertEqual(buffer.frameLength, 512)
                let left = try XCTUnwrap(buffer.floatChannelData)[0]
                for index in 0..<512 {
                    if previous <= 0 && left[index] > 0 { crossings += 1 }
                    previous = left[index]
                }
            }
            XCTAssertEqual(Double(crossings), track == 0 ? 440 : 881, accuracy: 15)
        }
        XCTAssertEqual(try output.engine.renderOffline(512, to: buffer), .success)
        let planes = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 {
            XCTAssertTrue((0..<512).allSatisfy { planes[channel][$0] == 0 })
        }
    }
}
