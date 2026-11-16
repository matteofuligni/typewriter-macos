import CryptoKit
import Foundation

public struct TeXInstallation: Sendable {
    public static let repository = URL(string: "https://mirrors.mit.edu/CTAN/systems/texlive/tlnet/")!
    private static let system = URL(fileURLWithPath: "/Library/TeX/texbin/pdflatex")
    private static let platforms = ["universal-darwin", "aarch64-darwin"]

    public let directory: URL
    private var marker: URL { directory.appendingPathComponent("current") }

    public init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Typewriter/TeXLive", isDirectory: true)) {
        self.directory = directory
    }

    public var installedBin: URL? {
        currentVersion.flatMap(Self.bin(in:))
    }

    private var currentVersion: URL? {
        guard let value = try? String(contentsOf: marker, encoding: .utf8),
              let id = UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return versionDirectory(id)
    }

    public var executable: URL? { installedBin?.appendingPathComponent("pdflatex") }

    public static var hasSystemEngine: Bool {
        FileManager.default.isExecutableFile(atPath: system.path)
    }

    private func versionDirectory(_ id: UUID) -> URL {
        directory.appendingPathComponent("versions/\(id.uuidString)", isDirectory: true)
    }

    private static func bin(in root: URL) -> URL? {
        platforms.lazy.map { root.appendingPathComponent("bin/\($0)", isDirectory: true) }.first {
            let fm = FileManager.default
            return fm.isExecutableFile(atPath: $0.appendingPathComponent("pdflatex").path)
                && fm.isExecutableFile(atPath: $0.appendingPathComponent("tlmgr").path)
        }
    }

    public func install(progress: @Sendable (String) async -> Void) async throws {
        let fm = FileManager.default
        let work = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: work) }
        let version = UUID()
        let runtime = versionDirectory(version)
        let previous = currentVersion
        let addedPackages = previous.map(readPackageList(in:)) ?? []
        try fm.createDirectory(at: runtime, withIntermediateDirectories: true)
        var activated = false
        defer { if !activated { try? fm.removeItem(at: runtime) } }

        let filename = "install-tl-unx.tar.gz"
        await progress("Downloading the installer…")
        let checksum = try await download(Self.repository.appendingPathComponent(filename + ".sha512"))
        let archive = try await download(Self.repository.appendingPathComponent(filename))
        guard Self.matchesChecksum(archive, declaration: checksum) else {
            throw LatexFailure("The installer checksum did not match. Try again shortly.")
        }
        try archive.write(to: work.appendingPathComponent(filename), options: .atomic)
        _ = try await run("/usr/bin/tar", ["-xzf", filename], in: work, timeout: 60)
        let installer = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first {
            $0.lastPathComponent.hasPrefix("install-tl-") &&
                fm.isRegularFile(at: $0.appendingPathComponent("install-tl"))
        }?.appendingPathComponent("install-tl")
        guard let installer else { throw LatexFailure("The TeX Live installer is incomplete.") }

        let profile = work.appendingPathComponent("typewriter.profile")
        try Data(Self.profile(for: runtime).utf8).write(to: profile)
        await progress("Downloading packages and setting up TeX Live…")
        _ = try await run("/usr/bin/perl", [
            installer.path, "-profile", profile.path, "-repository", Self.repository.absoluteString,
            "-no-gui", "-no-continue"
        ], in: work, timeout: 2_700)
        guard let bin = Self.bin(in: runtime) else { throw LatexFailure("The installation did not produce a usable LaTeX engine.") }
        if !addedPackages.isEmpty {
            await progress("Restoring extra packages…")
            _ = try await tlmgr(["install"] + addedPackages, bin: bin, in: work, timeout: 900)
            try writePackageList(addedPackages, in: runtime)
        }

        await progress("Checking the engine and the LaTeX template…")
        let engine = bin.appendingPathComponent("pdflatex")
        let compiler = LatexCompiler(bundledRoot: nil, systemExecutable: nil, managedExecutable: engine)
        do {
            _ = try await compiler.compile(WritingTemplates.latex, documentURL: nil)
        } catch let failure as LatexFailure where failure.missingPackageFile == "lmodern.sty" {
            _ = try await tlmgr(["install", "lm"], bin: bin, in: work, timeout: 600)
            _ = try await compiler.compile(WritingTemplates.latex, documentURL: nil)
        }
        try Task.checkCancellation()
        try Data(version.uuidString.utf8).write(to: marker, options: .atomic)
        activated = true
        if let previous { try? fm.removeItem(at: previous) }
    }

    public func packages(containing filename: String) async throws -> [String] {
        guard let bin = installedBin else { throw LatexFailure("Install TeX Live from Typewriter first.") }
        guard Self.validName(filename) else { throw LatexFailure("Invalid LaTeX filename.") }
        let work = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let pattern = "/" + NSRegularExpression.escapedPattern(for: filename) + "$"
        let output = try await tlmgr(["search", "--global", "--file", pattern], bin: bin, in: work, timeout: 120)
        return Self.packageNames(in: output, matching: filename)
    }

    public func installPackage(_ package: String) async throws {
        guard let root = currentVersion, let bin = Self.bin(in: root) else { throw LatexFailure("Install TeX Live from Typewriter first.") }
        guard Self.validName(package) else { throw LatexFailure("Enter a TeX Live package name.") }
        let work = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        _ = try await tlmgr(["install", package], bin: bin, in: work, timeout: 900)
        let packages = readPackageList(in: root)
        if !packages.contains(package) { try writePackageList(packages + [package], in: root) }
    }

    private func readPackageList(in root: URL) -> [String] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("typewriter-packages.json")),
              let packages = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return packages.filter(Self.validName)
    }

    private func writePackageList(_ packages: [String], in root: URL) throws {
        try JSONEncoder().encode(packages).write(to: root.appendingPathComponent("typewriter-packages.json"), options: .atomic)
    }

    public static func validName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.+-]{0,127}\z"#, options: .regularExpression) != nil
    }

    static func packageNames(in output: String, matching filename: String) -> [String] {
        var names: [String] = []
        var package: String?
        for line in output.split(whereSeparator: \.isNewline) {
            if line.last == ":", let first = line.first, !first.isWhitespace {
                let value = String(line.dropLast())
                package = validName(value) ? value : nil
            } else if let name = package, line.trimmingCharacters(in: .whitespaces).hasSuffix("/" + filename),
                      !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    static func matchesChecksum(_ data: Data, declaration: Data) -> Bool {
        guard let expected = String(data: declaration, encoding: .utf8)?
            .split(whereSeparator: \.isWhitespace).first, expected.count == 128 else { return false }
        let computed = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return computed == expected.lowercased()
    }

    static func profile(for root: URL) -> String {
        """
        selected_scheme scheme-small
        binary_universal-darwin 1
        TEXDIR \(root.path)
        TEXMFLOCAL \(root.appendingPathComponent("texmf-local").path)
        TEXMFHOME \(root.appendingPathComponent("texmf-home").path)
        TEXMFCONFIG \(root.appendingPathComponent("texmf-config").path)
        TEXMFVAR \(root.appendingPathComponent("texmf-var").path)
        TEXMFSYSCONFIG \(root.appendingPathComponent("texmf-config").path)
        TEXMFSYSVAR \(root.appendingPathComponent("texmf-var").path)
        instopt_adjustpath 0
        instopt_adjustrepo 1
        instopt_letter 0
        instopt_write18_restricted 0
        tlpdbopt_install_docfiles 0
        tlpdbopt_install_srcfiles 0
        """ + "\n"
    }

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 45))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.host == Self.repository.host, http.url?.scheme == "https" else {
            throw LatexFailure("The TeX Live server did not return the requested file.")
        }
        return data
    }

    private func makeTemporaryDirectory() throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("Typewriter-TeX-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return work
    }

    private func tlmgr(_ arguments: [String], bin: URL, in work: URL, timeout: TimeInterval) async throws -> String {
        try await run("/usr/bin/perl", [
            bin.appendingPathComponent("tlmgr").path,
            "--repository", Self.repository.absoluteString, "--verify-repo=main"
        ] + arguments, in: work, timeout: timeout, bin: bin)
    }

    private func run(_ executable: String, _ arguments: [String], in work: URL,
                     timeout: TimeInterval, bin: URL? = nil) async throws -> String {
        let home = work.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let env = [
            "PATH": (bin.map { $0.path + ":" } ?? "") + "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home.path, "TMPDIR": work.path, "LC_ALL": "en_US.UTF-8"
        ]
        let log = work.appendingPathComponent("install.log")
        let status = try await TeXProcess.execute(
            URL(fileURLWithPath: executable), arguments, in: work, environment: env, log: log,
            timeout: timeout, timeoutMessage: "The TeX Live operation timed out. Try again."
        )
        let bytes = try Data(contentsOf: log)
        let output = String(decoding: bytes, as: UTF8.self)
        guard status == 0 else {
            let lower = output.lowercased()
            let releaseMismatch = lower.contains("cross release") ||
                (lower.contains("local tex live") && lower.contains("remote repository"))
            let summary = releaseMismatch
                ? "A new TeX Live release is available. Update the installation."
                : "The TeX Live operation failed."
            throw LatexFailure(summary, log: String(output.suffix(12_000)))
        }
        return output
    }
}

private extension FileManager {
    func isRegularFile(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
