import Foundation

public struct JSONRPCSequencer: Sendable {
    private var nextID = 1

    public init() {}

    public mutating func nextRequestID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

public struct LineBuffer: Sendable {
    private var storage = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        storage.append(data)
        var lines: [String] = []

        while let newline = storage.firstIndex(of: 0x0A) {
            var lineData = storage[..<newline]
            storage.removeSubrange(...newline)
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }

        return lines
    }
}

public protocol LineTransport: Sendable {
    var lines: AsyncStream<String> { get }
    func start() async throws
    func send(line: String) async throws
    func stop() async
}

public enum LineTransportError: Error, Equatable, Sendable {
    case alreadyStarted
    case notStarted
    case invalidLine
}

public final class ProcessLineTransport: LineTransport, @unchecked Sendable {
    public let lines: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation
    private let executableURL: URL
    private let arguments: [String]
    private let environmentOverrides: [String: String]
    private let lock = NSLock()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var lineBuffer = LineBuffer()
    private var hasFinished = false

    public init(
        executableURL: URL,
        arguments: [String] = ["app-server", "--stdio"],
        environmentOverrides: [String: String] = [:]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environmentOverrides = environmentOverrides
        let pair = AsyncStream<String>.makeStream()
        lines = pair.stream
        continuation = pair.continuation
    }

    public func start() async throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        if !environmentOverrides.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(
                environmentOverrides,
                uniquingKeysWith: { _, override in override }
            )
        }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let canStart = lock.withLock {
            guard self.process == nil else {
                return false
            }
            self.process = process
            inputHandle = inputPipe.fileHandleForWriting
            return true
        }
        guard canStart else {
            throw LineTransportError.alreadyStarted
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.acceptOutput(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self?.finish()
        }

        do {
            try process.run()
        } catch {
            finish()
            throw error
        }
    }

    public func send(line: String) async throws {
        guard !line.contains("\n") && !line.contains("\r") else {
            throw LineTransportError.invalidLine
        }
        guard let handle = lock.withLock({ inputHandle }) else {
            throw LineTransportError.notStarted
        }
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }

    public func stop() async {
        let current = lock.withLock { () -> Process? in
            inputHandle?.closeFile()
            inputHandle = nil
            let current = process
            process = nil
            return current
        }
        if let current, current.isRunning {
            current.terminate()
            for _ in 0..<40 {
                if !current.isRunning { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if current.isRunning { kill(current.processIdentifier, SIGKILL) }
        }
        finish()
    }

    private func acceptOutput(_ data: Data) {
        guard !data.isEmpty else {
            finish()
            return
        }
        let parsedLines = lock.withLock {
            lineBuffer.append(data)
        }
        for line in parsedLines {
            continuation.yield(line)
        }
    }

    private func finish() {
        let shouldFinish = lock.withLock {
            if hasFinished {
                return false
            }
            hasFinished = true
            return true
        }
        if shouldFinish {
            continuation.finish()
        }
    }
}
