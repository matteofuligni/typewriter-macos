import AppKit
import Observation
import TypewriterCore

enum PreviewStatus: Equatable {
    case waiting, rendering, ready(String), failed(String)
}

@MainActor @Observable
final class WorkspaceModel {
    var kind: DocumentKind = .latex
    var title = "Untitled"
    var source = ""
    var loadedRevision = 0
    var dirty = false
    var status = PreviewStatus.waiting
    var pdf: Data?
    var pdfRevision = 0
    var log = ""
    var words = 0
    var line = 1
    var column = 1
    var automatic = true {
        didSet { if automatic && oldValue != automatic && status != .rendering { schedule() } }
    }
    var showsNavigator = true
    var showsDependencies = false
    private(set) var typewriterMode = false
    var project = LatexProject()
    var inspectedFileID = LatexProject.rootID
    var navigation: Navigation?
    var missingPackageFile: String?

    struct Navigation: Equatable {
        let fileID: String
        let line: Int
        let id = UUID()
    }

    var inspectedFile: LatexProject.File? { project.files.first { $0.id == inspectedFileID && $0.id != LatexProject.rootID } }

    @ObservationIgnored weak var document: TypewriterDocument?
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var counter: Task<Void, Never>?
    @ObservationIgnored private var indexer: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func setDocument(_ value: String, kind: DocumentKind) {
        source = value
        self.kind = kind
        loadedRevision += 1
        inspectedFileID = LatexProject.rootID
        refreshProject()
        updateCount()
    }

    func edited(_ value: String) {
        guard value != source else { return }
        source = value
        document?.textDidChange()
        refreshProject(after: .milliseconds(260))
        updateCount()
        schedule()
    }

    func reveal(fileID: String, line: Int = 1) {
        inspectedFileID = fileID
        navigation = Navigation(fileID: fileID, line: line)
    }

    func toggleTypewriterMode() {
        typewriterMode.toggle()
        if typewriterMode { inspectedFileID = LatexProject.rootID }
    }

    func refreshProject(after delay: Duration = .zero) {
        indexer?.cancel()
        guard kind == .latex else { return }
        let snapshot = source
        let root = document?.fileURL
        indexer = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            let worker = Task.detached(priority: .utility) { LatexProject.index(source: snapshot, root: root) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled else { return }
            self.project = result
            if !result.files.contains(where: { $0.id == self.inspectedFileID }) {
                self.inspectedFileID = LatexProject.rootID
            }
        }
    }

    func compileNow() {
        refreshProject()
        schedule(immediate: true)
    }

    func pauseCompilation() {
        job?.cancel()
        generation += 1
        if status == .rendering { status = .waiting }
    }

    private func updateCount() {
        counter?.cancel()
        guard kind != .latex else { return }
        let snapshot = source
        counter = Task { [weak self] in
            let count = await Self.countWords(snapshot)
            if !Task.isCancelled { self?.words = count }
        }
    }

    private nonisolated static func countWords(_ snapshot: String) async -> Int {
        var words = 0
        var inWord = false
        for (index, scalar) in snapshot.unicodeScalars.enumerated() {
            if index.isMultiple(of: 4_096), Task.isCancelled { break }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else if !inWord {
                words += 1
                inWord = true
            }
        }
        return words
    }

    func schedule(immediate: Bool = false) {
        job?.cancel()
        generation += 1
        let version = generation
        status = .waiting
        log = ""
        missingPackageFile = nil
        let isLatex = kind == .latex
        if isLatex && TeXManager.shared.isInstalling { return }
        guard immediate || automatic || !isLatex else { return }
        let snapshot = source
        let url = document?.fileURL
        let managedEngine = isLatex ? TeXManager.shared.engine : nil
        job = Task { [weak self] in
            do {
                if !immediate { try await Task.sleep(for: isLatex ? .milliseconds(430) : .milliseconds(140)) }
                guard self?.generation == version else { return }
                self?.status = .rendering
                let result = try await Self.render(snapshot, isLatex: isLatex, url: url, managedEngine: managedEngine)
                guard !Task.isCancelled, let self, self.generation == version else { return }
                self.pdf = result.0
                self.pdfRevision += 1
                self.status = .ready(result.1)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, self.generation == version else { return }
                self.log = (error as? LatexFailure)?.log ?? ""
                self.missingPackageFile = (error as? LatexFailure)?.missingPackageFile
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    private nonisolated static func render(_ source: String, isLatex: Bool, url: URL?, managedEngine: URL?) async throws -> (Data, String) {
        if isLatex {
            let output = try await LatexCompiler(managedExecutable: managedEngine).compile(source, documentURL: url)
            let t = output.elapsed.components
            let milliseconds = t.seconds * 1000 + t.attoseconds / 1_000_000_000_000_000
            let elapsed = milliseconds < 1000 ? "\(milliseconds) ms" : String(format: "%.1f s", Double(milliseconds) / 1000)
            return (output.pdf, "\(output.engine) · \(elapsed)")
        }
        return (try PrintLayout.pdf(for: source), "Native typesetting")
    }

    func stop() {
        job?.cancel()
        counter?.cancel()
        indexer?.cancel()
    }
}
