import AppKit
import SwiftUI
import TypewriterCore
import UniformTypeIdentifiers

@objc(TypewriterDocument)
@MainActor final class TypewriterDocument: NSDocument {
    let workspace = WorkspaceModel()

    override init() {
        super.init()
        workspace.document = self
    }

    override class var autosavesInPlace: Bool { false }

    override func defaultDraftName() -> String { "Untitled" }

    func initialize(kind: DocumentKind) {
        workspace.setDocument(kind == .latex ? WritingTemplates.latex : "", kind: kind)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let kind = Self.format(typeName) else { throw CocoaError(.fileReadUnknown) }
        let source = try kind.read(data)
        // Concurrent NSDocument reads are disabled, so AppKit calls this on the main thread.
        MainActor.assumeIsolated {
            workspace.setDocument(source, kind: kind)
            if !windowControllers.isEmpty { workspace.schedule(immediate: true) }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let kind = Self.format(typeName) else { throw CocoaError(.fileWriteUnknown) }
        return try kind.write(workspace.source)
    }

    private nonisolated static func format(_ typeName: String) -> DocumentKind? {
        switch typeName {
        case "LaTeX": .latex
        case "Word Document": .word
        case "Plain Text": .text
        default: DocumentKind.kind(for: typeName)
        }
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1260, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.minSize = NSSize(width: 900, height: 590)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Ink.nsHeader
        window.isMovableByWindowBackground = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: WorkspaceView(model: workspace))
        window.center()
        window.setFrameAutosaveName("TypewriterWorkspace")
        addWindowController(WorkspaceWindowController(window: window))
        workspace.title = displayName
        workspace.compileNow()
    }

    func textDidChange() {
        // NSTextView registers undo with the document's manager, which updates its change count.
        if undoManager == nil { updateChangeCount(.changeDone) }
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        workspace.dirty = isDocumentEdited
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        workspace.dirty = isDocumentEdited
        guard workspace.kind == .latex,
              saveOperation == .saveOperation || saveOperation == .saveAsOperation,
              let url = fileURL?.resolvingSymlinksInPath().standardizedFileURL else { return }
        for case let other as TypewriterDocument in NSDocumentController.shared.documents where other !== self {
            if other.workspace.project.files.contains(where: { $0.url == url }) {
                other.workspace.refreshProject()
                other.workspace.schedule()
            }
        }
    }

    override func close() {
        workspace.stop()
        super.close()
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        let identifier = workspace.kind.rawValue
        let type = UTType(identifier) ?? UTType(filenameExtension: workspace.kind.fileExtension) ?? .plainText
        savePanel.allowedContentTypes = [type]
        if fileURL == nil { savePanel.nameFieldStringValue = "Untitled.\(workspace.kind.fileExtension)" }
        return true
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [fileType ?? DocumentKind.latex.rawValue]
    }

    func saveFromToolbar() {
        save(self)
    }

    func openLinkedFile() {
        guard let url = workspace.inspectedFile?.url else { return }
        let line = workspace.navigation?.line ?? 1
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] opened, _, error in
            if let error { self?.presentError(error) }
            (opened as? TypewriterDocument)?.workspace.reveal(fileID: LatexProject.rootID, line: line)
        }
    }

    func exportPDF() {
        guard case .ready = workspace.status, let data = workspace.pdf,
              let window = windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.title = "Export PDF"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        let name = (displayName as NSString).deletingPathExtension
        panel.nameFieldStringValue = name + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic) } catch { self?.presentError(error) }
        }
    }
}

@MainActor private final class WorkspaceWindowController: NSWindowController {
    private var lastURL: URL?

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        if let document = document as? TypewriterDocument {
            document.workspace.title = document.displayName
            if document.fileURL != lastURL {
                lastURL = document.fileURL
                if document.workspace.kind == .latex && lastURL != nil {
                    document.workspace.compileNow()
                }
            }
        }
    }
}
