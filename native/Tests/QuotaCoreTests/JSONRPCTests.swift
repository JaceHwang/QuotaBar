import Foundation
import XCTest
@testable import QuotaCore

final class JSONRPCTests: XCTestCase {
    func testRequestIDsIncrease() {
        var sequencer = JSONRPCSequencer()

        XCTAssertEqual(sequencer.nextRequestID(), 1)
        XCTAssertEqual(sequencer.nextRequestID(), 2)
        XCTAssertEqual(sequencer.nextRequestID(), 3)
    }

    func testPartialLinesBufferUntilNewline() {
        var buffer = LineBuffer()

        XCTAssertEqual(buffer.append(Data(#"{"id":1"#.utf8)), [])
        XCTAssertEqual(buffer.append(Data("}\n".utf8)), [#"{"id":1}"#])
    }

    func testMultipleLinesAreEmittedSeparately() {
        var buffer = LineBuffer()

        let lines = buffer.append(Data("{\"id\":1}\n{\"id\":2}\n".utf8))

        XCTAssertEqual(lines, [#"{"id":1}"#, #"{"id":2}"#])
    }

    func testProcessTransportAppliesEnvironmentOverrides() async throws {
        let transport = ProcessLineTransport(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                #"printf 'CODEX_HOME=%s\n' "$CODEX_HOME"; read input"#,
            ],
            environmentOverrides: ["CODEX_HOME": "/tmp/plugin-codex-home"]
        )

        try await transport.start()
        var iterator = transport.lines.makeAsyncIterator()
        let line = await iterator.next()
        await transport.stop()

        XCTAssertEqual(line, "CODEX_HOME=/tmp/plugin-codex-home")
    }
}
