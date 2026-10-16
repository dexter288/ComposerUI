import ComposerCore
import Foundation

/// Launches one `composer` process, streams its output line by line and supports cancellation.
/// Arguments are passed as argv; no shell is involved.
struct ProcessRunner: Sendable {
    let toolchain: ComposerToolchain

    struct Launch {
        let process: Process
        let lines: AsyncStream<CommandOutputLine>
    }

    func launch(_ command: ComposerCommand) throws -> Launch {
        let process = Process()
        process.executableURL = toolchain.php
        process.arguments = [toolchain.composer.path] + command.arguments
        process.currentDirectoryURL = command.workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        process.environment = environment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let (stream, continuation) = AsyncStream<CommandOutputLine>.makeStream()
        let counter = LineCounter()
        let outDecoder = LineDecoder(stream: .stdout, counter: counter, continuation: continuation)
        let errDecoder = LineDecoder(stream: .stderr, counter: counter, continuation: continuation)
        let group = DispatchGroup()
        group.enter()
        group.enter()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                outDecoder.finish()
                group.leave()
            } else {
                outDecoder.feed(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                errDecoder.finish()
                group.leave()
            } else {
                errDecoder.feed(data)
            }
        }
        group.notify(queue: .global()) {
            continuation.finish()
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            continuation.finish()
            throw CommandError.launchFailed(error.localizedDescription)
        }
        return Launch(process: process, lines: stream)
    }

    func environment() -> [String: String] {
        let home = NSHomeDirectory()
        var env: [String: String] = [
            "PATH": toolchain.path,
            "HOME": home,
            "USER": NSUserName(),
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "TERM": "dumb",
            "COMPOSER_HOME": toolchain.composerHome.path,
            "COMPOSER_NO_INTERACTION": "1",
            "COMPOSER_DISABLE_XDEBUG_WARN": "1",
            "NO_COLOR": "1",
        ]
        // Pass through the few variables Composer and git legitimately read for auth.
        for key in ["COMPOSER_AUTH", "SSH_AUTH_SOCK", "TMPDIR", "GIT_SSH_COMMAND", "https_proxy", "http_proxy", "HTTPS_PROXY", "HTTP_PROXY", "no_proxy"] {
            if let value = ProcessInfo.processInfo.environment[key] { env[key] = value }
        }
        return env
    }
}

/// Hands out increasing line IDs across both streams.
final class LineCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var next = 0
    func take() -> Int {
        lock.lock(); defer { lock.unlock() }
        next += 1
        return next
    }
}

/// Splits a byte stream into UTF-8 lines, tolerating split multibyte sequences and `\r` progress updates.
final class LineDecoder: @unchecked Sendable {
    private let stream: CommandOutputLine.Stream
    private let counter: LineCounter
    private let continuation: AsyncStream<CommandOutputLine>.Continuation
    private var buffer = Data()
    private let lock = NSLock()

    init(stream: CommandOutputLine.Stream, counter: LineCounter, continuation: AsyncStream<CommandOutputLine>.Continuation) {
        self.stream = stream
        self.counter = counter
        self.continuation = continuation
    }

    func feed(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            emit(lineData)
        }
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        if !buffer.isEmpty {
            emit(buffer)
            buffer.removeAll()
        }
    }

    private func emit(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        guard !text.isEmpty else { return }
        continuation.yield(CommandOutputLine(id: counter.take(), stream: stream, text: text))
    }
}
