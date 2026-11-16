import Foundation

public struct LatexFailure: LocalizedError, Sendable {
    public let reason: String
    public let log: String

    public var errorDescription: String? { reason }
    public var missingPackageFile: String? {
        let pattern = #"File [\x60'‘]([A-Za-z0-9][A-Za-z0-9_+.-]*\.(?:sty|cls|def|ldf|fd|bbx|cbx|bst))[\x27'’] not found"#
        guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(
            in: log, range: NSRange(log.startIndex..., in: log)
        ), let range = Range(match.range(at: 1), in: log) else { return nil }
        return String(log[range])
    }

    public init(_ reason: String, log: String = "") {
        self.reason = reason
        self.log = log
    }
}

public struct LatexResult: Sendable {
    public let pdf: Data
    public let passes: Int
    public let elapsed: Duration
    public let engine: String
}

public struct LatexCompiler: Sendable {
    public var bundledRoot: URL?
    public var systemExecutable: URL?
    public var managedExecutable: URL?

    public init(
        bundledRoot: URL? = Bundle.main.resourceURL?.appendingPathComponent("TeX"),
        systemExecutable: URL? = URL(fileURLWithPath: "/Library/TeX/texbin/pdflatex"),
        managedExecutable: URL? = nil
    ) {
        self.bundledRoot = bundledRoot
        self.systemExecutable = systemExecutable
        self.managedExecutable = managedExecutable
    }

    public func compile(_ source: String, documentURL: URL?) async throws -> LatexResult {
        let fm = FileManager.default
        if let managedExecutable, fm.isExecutableFile(atPath: managedExecutable.path) {
            return try await run(source, documentURL: documentURL, executable: managedExecutable, root: nil)
        }
        let embedded = bundledRoot?.appendingPathComponent("bin/pdflatex")
        let availableSystem = systemExecutable.flatMap { fm.isExecutableFile(atPath: $0.path) ? $0 : nil }
        if let embedded, fm.isExecutableFile(atPath: embedded.path), let bundledRoot {
            do {
                return try await run(source, documentURL: documentURL, executable: embedded, root: bundledRoot)
            } catch let error as LatexFailure where error.log.range(
                of: #"File [\x60'].*\.(sty|cls|def|ldf|fd|tfm|pfb)[\x27'] not found|Metric \(TFM\) file not found|cannot open Type 1 font"#,
                options: .regularExpression
            ) != nil {
                try Task.checkCancellation()
                if let availableSystem {
                    return try await run(source, documentURL: documentURL, executable: availableSystem, root: nil)
                }
                throw error
            }
        }
        if let availableSystem {
            return try await run(source, documentURL: documentURL, executable: availableSystem, root: nil)
        }
        throw LatexFailure("Install LaTeX to compile.", log: "Open LaTeX Dependencies and choose Install TeX Live.")
    }

    private func run(_ source: String, documentURL: URL?, executable: URL, root: URL?) async throws -> LatexResult {
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let started = clock.now
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("Typewriter-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }
        let filename = documentURL?.lastPathComponent ?? "document.tex"
        let stem = (filename as NSString).deletingPathExtension
        let sourceURL = work.appendingPathComponent(filename)
        let pdfURL = work.appendingPathComponent(stem + ".pdf")
        let traceURL = work.appendingPathComponent("compilation.txt")
        try Data(source.utf8).write(to: sourceURL)
        let linkedAuxFiles = try prepareLinkedDirectories(source: source, documentURL: documentURL, in: work)

        var env = [
            "PATH": executable.deletingLastPathComponent().path + ":/usr/bin:/bin",
            "HOME": work.path, "TMPDIR": work.path, "LC_ALL": "en_US.UTF-8",
            "openin_any": "p", "openout_any": "p",
            "MKTEXPK": "0", "MKTEXTFM": "0"
        ]
        if let root { env["TEXMFCNF"] = root.path }
        // Local files are resolved beside the original document; generated files stay in work.
        if let folder = documentURL?.deletingLastPathComponent().path,
           !folder.contains(":"), !folder.contains("$"), !folder.contains("{"), !folder.contains("}") {
            env["TEXINPUTS"] = ".:\(folder):"
        }
        let args = [
            "-no-shell-escape", "-no-mktex=pk", "-no-mktex=tfm", "-halt-on-error",
            "-file-line-error", "-interaction=nonstopmode", "./" + filename
        ]

        let mainReferenceFiles = ["aux", "toc", "lof", "lot", "out"].map { stem + "." + $0 }
        let referenceFiles = mainReferenceFiles + linkedAuxFiles
        for pass in 1...3 {
            try Task.checkCancellation()
            let before = referenceState(in: work, paths: referenceFiles)
            let status = try await TeXProcess.execute(executable, args, in: work, environment: env, log: traceURL)
            let log = readLog(traceURL)
            guard status == 0, fm.fileExists(atPath: pdfURL.path) else {
                throw LatexFailure(Self.summary(in: log), log: log)
            }
            let after = referenceState(in: work, paths: referenceFiles)
            let wantsRerun = log.contains("Rerun to get") || log.contains("rerunfilecheck Warning")
                || log.contains("There were undefined references")
            let hasStructure = after.keys.contains { $0 != stem + ".aux" }
            if pass == 3 || before == after || (!wantsRerun && !hasStructure) {
                return LatexResult(
                    pdf: try Data(contentsOf: pdfURL), passes: pass,
                    elapsed: started.duration(to: clock.now), engine: root == nil ? "TeX Live" : "pdfLaTeX"
                )
            }
        }
        throw LatexFailure("Compilation failed.")
    }

    private func prepareLinkedDirectories(source: String, documentURL: URL?, in work: URL) throws -> [String] {
        guard let documentURL else { return [] }
        let project = LatexProject.index(source: source, root: documentURL)
        var prepared: Set<String> = []
        var auxiliaries: [String] = []
        for file in project.files.dropFirst() {
            let folder = (file.name as NSString).deletingLastPathComponent
            if !folder.isEmpty, prepared.insert(folder).inserted {
                try FileManager.default.createDirectory(at: work.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            auxiliaries.append((file.name as NSString).deletingPathExtension + ".aux")
        }
        return auxiliaries
    }

    private func referenceState(in directory: URL, paths: [String]) -> [String: Data] {
        var result: [String: Data] = [:]
        for path in paths {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(path)), !data.isEmpty {
                result[path] = data
            }
        }
        return result
    }

    private func readLog(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let size = try? handle.seekToEnd() else { return "" }
        try? handle.seek(toOffset: size > 49_152 ? size - 49_152 : 0)
        guard let bytes = try? handle.read(upToCount: 49_152) else { return "" }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func summary(in log: String) -> String {
        for line in log.split(separator: "\n") {
            if let match = line.range(of: #"\.tex:[0-9]+:"# , options: .regularExpression) {
                let number = line[match].split(separator: ":")[1]
                let detail = line[match.upperBound...].trimmingCharacters(in: .whitespaces)
                return "Line \(number): \(detail)"
            }
            if line.hasPrefix("! ") { return String(line.dropFirst(2)) }
        }
        return "LaTeX did not produce a PDF."
    }
}

// The lock protects process lifetime against cancellation racing with start or exit.
final class TeXProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    static func execute(
        _ executable: URL, _ arguments: [String], in directory: URL,
        environment: [String: String], log: URL,
        timeout: TimeInterval = 15, timeoutMessage: String = "Compilation timed out after 15 seconds."
    ) async throws -> Int32 {
        let gate = TeXProcess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try gate.run(executable, arguments, in: directory, environment: environment, log: log,
                                     timeout: timeout, timeoutMessage: timeoutMessage)
                    })
                }
            }
        } onCancel: {
            gate.stop(timeout: false)
        }
    }

    private func run(
        _ executable: URL, _ arguments: [String], in directory: URL,
        environment: [String: String], log: URL, timeout: TimeInterval, timeoutMessage: String
    ) throws -> Int32 {
        try Data().write(to: log)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = directory
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = output

        try lock.withLock {
            if cancelled { throw CancellationError() }
            try child.run()
            process = child
        }
        let deadline = DispatchWorkItem { [weak self] in self?.stop(timeout: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        child.waitUntilExit()
        deadline.cancel()
        return try lock.withLock {
            process = nil
            if cancelled { throw CancellationError() }
            if timedOut { throw LatexFailure(timeoutMessage) }
            return child.terminationStatus
        }
    }

    private func stop(timeout: Bool) {
        lock.withLock {
            if timeout {
                guard process?.isRunning == true else { return }
                timedOut = true
            } else {
                cancelled = true
            }
            guard let process, process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [weak self, weak process] in
                guard let self, let process else { return }
                self.lock.withLock {
                    if self.process === process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }
}
