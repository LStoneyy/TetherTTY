import XCTest
import NIOCore
import NIOEmbedded
@preconcurrency import NIOSSH
@testable import TetherTTY

/// Fixture tests for Phase 3 of the SSH trust-boundary remediation (SEC-05, SEC-06):
/// - `ExecCommandHandler` bounds combined stdout+stderr output and enforces an overall exec
///   deadline, completing the continuation exactly once and always closing the channel.
/// - No production source file logs sensitive values (host, username, key material, fingerprint,
///   command text, or remote command output) via `print(...)`.
final class ResourceLoggingSecurityTests: XCTestCase {

    // MARK: - Helpers

    /// Adds an `ExecCommandHandler` to `channel`, synchronously runs `drive` against the channel
    /// (writing inbound data and/or advancing the embedded event loop's virtual clock), and
    /// returns whatever the handler ultimately resolves the continuation with.
    ///
    /// Everything here — creating the continuation, adding the handler, and driving the channel —
    /// happens inside a single synchronous closure body, so it all runs on the thread that entered
    /// this `async` function, which is required for `EmbeddedEventLoop`'s single-thread contract.
    private func runHandler(
        channel: EmbeddedChannel,
        outputLimit: Int = ExecCommandHandler.defaultOutputLimit,
        deadline: TimeAmount = ExecCommandHandler.defaultDeadline,
        drive: @escaping (EmbeddedChannel) -> Void
    ) async throws -> SSHExecResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SSHExecResult, Error>) in
            let handler = ExecCommandHandler(
                command: "test-command",
                continuation: continuation,
                allocator: channel.allocator,
                outputLimit: outputLimit,
                deadline: deadline
            )
            try! channel.pipeline.syncOperations.addHandler(handler)
            drive(channel)
        }
    }

    // MARK: - SEC-05: combined stdout+stderr output limit

    func testExecOutputLimitCombined() async throws {
        let channel = EmbeddedChannel()

        do {
            _ = try await runHandler(channel: channel, outputLimit: 1_048_576) { channel in
                // Neither chunk alone exceeds the limit, but stdout+stderr combined (1,100,000
                // bytes) does — proving the limit is enforced across BOTH streams combined,
                // not per-stream.
                var stdoutChunk = channel.allocator.buffer(capacity: 600_000)
                stdoutChunk.writeRepeatingByte(0x41, count: 600_000)
                try! channel.writeInbound(SSHChannelData(type: .channel, data: .byteBuffer(stdoutChunk)))

                var stderrChunk = channel.allocator.buffer(capacity: 500_000)
                stderrChunk.writeRepeatingByte(0x42, count: 500_000)
                try! channel.writeInbound(SSHChannelData(type: .stdErr, data: .byteBuffer(stderrChunk)))
            }
            XCTFail("Expected exceeding the combined output limit to fail the command")
        } catch let error as SSHClientError {
            XCTAssertEqual(error, .outputLimitExceeded)
        }

        XCTAssertFalse(channel.isActive, "Exceeding the output limit must close the channel")
    }

    func testOutputWithinLimitSucceeds() async throws {
        let channel = EmbeddedChannel()

        let result = try await runHandler(channel: channel, outputLimit: 1_048_576) { channel in
            var stdoutChunk = channel.allocator.buffer(capacity: 4)
            stdoutChunk.writeString("ok\n")
            try! channel.writeInbound(SSHChannelData(type: .channel, data: .byteBuffer(stdoutChunk)))
            channel.pipeline.fireUserInboundEventTriggered(SSHChannelRequestEvent.ExitStatus(exitStatus: 0))
        }

        XCTAssertEqual(result.stdout, "ok\n")
        XCTAssertEqual(result.exitStatus, 0)
    }

    // MARK: - SEC-05: overall exec deadline

    func testExecCommandTimeout() async throws {
        let channel = EmbeddedChannel()

        do {
            _ = try await runHandler(channel: channel, deadline: .milliseconds(5)) { channel in
                // Simulate a hung remote command: nothing is ever written, so only the deadline
                // can complete this exec. Advancing the embedded loop's virtual clock fires the
                // deadline deterministically, without the test actually waiting 5ms (or 15s).
                channel.embeddedEventLoop.advanceTime(by: .milliseconds(5))
            }
            XCTFail("Expected the exec deadline to fail the command")
        } catch let error as SSHClientError {
            XCTAssertEqual(error, .executionTimedOut)
        }
    }

    func testTimeoutClosesChannel() async throws {
        let channel = EmbeddedChannel()

        _ = try? await runHandler(channel: channel, deadline: .milliseconds(5)) { channel in
            channel.embeddedEventLoop.advanceTime(by: .milliseconds(5))
        }

        XCTAssertFalse(channel.isActive, "A timed-out command must close the channel")
    }

    func testDefaultDeadlineIsFifteenSeconds() {
        XCTAssertEqual(ExecCommandHandler.defaultDeadline, .seconds(15))
    }

    func testDefaultOutputLimitIsOneMebibyte() {
        XCTAssertEqual(ExecCommandHandler.defaultOutputLimit, 1_048_576)
    }

    // MARK: - Exactly-once completion

    /// Exercises the output-limit path racing against the deadline: after the output limit has
    /// already completed (and cancelled) the deadline, later firing the (cancelled) deadline task
    /// or finishing the channel must be a complete no-op — not a second continuation resume, which
    /// would crash (`CheckedContinuation` traps on double-resume).
    func testExactlyOnceCompletion() async throws {
        let channel = EmbeddedChannel()

        do {
            _ = try await runHandler(channel: channel, outputLimit: 16, deadline: .milliseconds(5)) { channel in
                var chunk = channel.allocator.buffer(capacity: 32)
                chunk.writeRepeatingByte(0x41, count: 32)
                try! channel.writeInbound(SSHChannelData(type: .channel, data: .byteBuffer(chunk)))
            }
            XCTFail("Expected exceeding the output limit to fail the command")
        } catch let error as SSHClientError {
            XCTAssertEqual(error, .outputLimitExceeded)
        }

        // The handler already completed synchronously above (and cancelled its deadline task in
        // the process), closing the channel. Advancing time further and tearing the (already
        // closed) channel down must not attempt to resume the (already-resumed) continuation a
        // second time — reaching the assertions below without a crash IS the test.
        channel.embeddedEventLoop.advanceTime(by: .milliseconds(50))
        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
        XCTAssertFalse(channel.isActive)
    }

    /// A normal successful completion followed by the channel becoming inactive (as always
    /// happens once `context.close()` finishes tearing the channel down) must not attempt to
    /// resume the continuation again.
    func testExactlyOnceCompletionAfterSuccessAndChannelInactive() async throws {
        let channel = EmbeddedChannel()

        let result = try await runHandler(channel: channel) { channel in
            channel.pipeline.fireUserInboundEventTriggered(SSHChannelRequestEvent.ExitStatus(exitStatus: 0))
        }

        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
        XCTAssertFalse(channel.isActive)
    }

    // MARK: - SEC-06: no sensitive print() logging in production code

    /// Static guard: no `.swift` file under the `TetherTTY/` production source directory may
    /// contain a `print(` call. Locates the production source directory relative to this test
    /// file's `#filePath` (repo root is two levels up: `TetherTTYTests/<this file>` ->
    /// `<repoRoot>/TetherTTY`). If the test bundle cannot reliably see the source tree on disk,
    /// this test is skipped (not failed) — enforce via `rg -n 'print\(' TetherTTY/ --type swift`
    /// in CI instead.
    func testNoPrintStatements() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent() // ResourceLoggingSecurityTests.swift
            .deletingLastPathComponent() // TetherTTYTests
        let productionDir = repoRoot.appendingPathComponent("TetherTTY", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: productionDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw XCTSkip(
                "Could not locate production source directory at \(productionDir.path) from the test " +
                "bundle; enforce this via `rg -n 'print\\(' TetherTTY/ --type swift` in CI instead."
            )
        }

        guard let enumerator = FileManager.default.enumerator(
            at: productionDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw XCTSkip(
                "Could not enumerate \(productionDir.path) from the test bundle; enforce this via " +
                "`rg -n 'print\\(' TetherTTY/ --type swift` in CI instead."
            )
        }

        // Matches a genuine `print(` call, but not identifiers that merely end in "print(" (e.g.
        // `fingerprint(`), by requiring the character immediately before "print" to not be part of
        // an identifier.
        let printCallRegex = try NSRegularExpression(pattern: "(?<![A-Za-z0-9_])print\\(")

        var offenders: [String] = []
        var sawAnySwiftFile = false
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            sawAnySwiftFile = true
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let range = NSRange(contents.startIndex..., in: contents)
            if printCallRegex.firstMatch(in: contents, range: range) != nil {
                offenders.append(fileURL.lastPathComponent)
            }
        }

        guard sawAnySwiftFile else {
            throw XCTSkip(
                "Enumerated \(productionDir.path) but found no .swift files from the test bundle; " +
                "enforce this via `rg -n 'print\\(' TetherTTY/ --type swift` in CI instead."
            )
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Found print( in production source file(s): \(offenders.joined(separator: ", "))"
        )
    }
}
