import AppKit
import Observation
import SwiftUI
import TypewriterCore

@MainActor @Observable
final class TeXManager {
    static let shared = TeXManager()
    private let installation = TeXInstallation()

    private(set) var engine: URL?
    private(set) var activity: String?
    private(set) var isInstalling = false
    private(set) var error: String?
    private(set) var log = ""
    private(set) var completed: String?
    private(set) var isChecking = false
    private(set) var startupFailure: LatexFailure?
    @ObservationIgnored private var environmentCheck: Task<Void, Never>?
    @ObservationIgnored private var promptedForSetup = false

    var isAvailable: Bool {
        engine != nil || TeXInstallation.hasSystemEngine || bundledEngine
    }

    private var bundledEngine: Bool {
        guard let path = Bundle.main.resourceURL?.appendingPathComponent("TeX/bin/pdflatex").path else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    var engineDescription: String {
        if engine != nil { return "TeX Live managed by Typewriter" }
        if bundledEngine { return "Bundled LaTeX engine" }
        if TeXInstallation.hasSystemEngine { return "System TeX Live detected" }
        return "No LaTeX engine installed"
    }

    init() {
        engine = installation.executable
    }

    func checkEnvironment() {
        guard !isInstalling else { return }
        environmentCheck?.cancel()
        engine = installation.executable
        let compiler = LatexCompiler(managedExecutable: engine)
        isChecking = true
        environmentCheck = Task { [weak self] in
            do {
                _ = try await compiler.compile(WritingTemplates.latex, documentURL: nil)
                guard !Task.isCancelled else { return }
                self?.startupFailure = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.startupFailure = error as? LatexFailure ?? LatexFailure(error.localizedDescription)
            }
            self?.isChecking = false
        }
    }

    func claimSetupPrompt() -> Bool {
        guard startupFailure != nil, !isChecking, !isInstalling, !promptedForSetup else { return false }
        promptedForSetup = true
        return true
    }

    func installBase() async {
        await perform("Preparing installation…", installing: true) {
            try await self.installation.install { [weak self] message in
                await self?.setActivity(message)
            }
            self.engine = self.installation.executable
            self.startupFailure = nil
            self.completed = "TeX Live is ready."
        }
    }

    func installPackage(_ name: String) async {
        await perform("Installing \(name)…", installing: true) {
            try await self.installation.installPackage(name)
            self.completed = "Installed \(name)."
        }
    }

    func findPackages(for filename: String) async -> [String]? {
        var results: [String]?
        await perform("Searching CTAN for \(filename)…", installing: false) {
            results = try await self.installation.packages(containing: filename)
        }
        return results
    }

    private func setActivity(_ message: String) { activity = message }

    private func perform(_ message: String, installing: Bool, operation: () async throws -> Void) async {
        guard activity == nil else { return }
        error = nil
        log = ""
        completed = nil
        activity = message
        isInstalling = installing
        let documents = NSDocumentController.shared.documents.compactMap { ($0 as? TypewriterDocument)?.workspace }
        if installing {
            environmentCheck?.cancel()
            isChecking = false
            for workspace in documents where workspace.kind == .latex { workspace.pauseCompilation() }
        }
        do {
            try await operation()
        } catch {
            self.error = error.localizedDescription
            log = (error as? LatexFailure)?.log ?? ""
        }
        activity = nil
        isInstalling = false
        if installing {
            if startupFailure != nil, error == nil { checkEnvironment() }
            for case let document as TypewriterDocument in NSDocumentController.shared.documents
                where document.workspace.kind == .latex && document.workspace.automatic {
                document.workspace.schedule(immediate: true)
            }
        }
    }
}

struct TeXDependenciesView: View {
    let manager = TeXManager.shared
    let suggestedFile: String?
    let close: () -> Void

    @State private var requestedPackage = ""
    @State private var candidates: [String]?
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LaTeX Dependencies").font(.custom("Baskerville", size: 30))
                Label(manager.engineDescription, systemImage: manager.isAvailable ? "checkmark.circle" : "shippingbox")
                    .foregroundStyle(manager.isAvailable ? Ink.text : Ink.muted)
                    .font(.system(size: 12, weight: .medium))
            }
            Text("Typewriter downloads TeX Live from CTAN and installs it for your user account. Installed packages work offline.")
                .font(.system(size: 12))
                .foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(manager.engine == nil ? "Install TeX Live" : "Update TeX Live") {
                Task { await manager.installBase() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Ink.forest)
            .disabled(manager.activity != nil)

            if manager.engine != nil {
                Divider()
                packageControls
            }
            if let activity = manager.activity {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(activity).font(.system(size: 12))
                }
                .accessibilityElement(children: .combine)
            }
            if let completed = manager.completed {
                Label(completed, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Ink.forest)
            }
            if let error = manager.error ?? (manager.activity == nil ? manager.startupFailure?.reason : nil) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(Ink.copper)
                let log = manager.error == nil ? (manager.startupFailure?.log ?? "") : manager.log
                if !log.isEmpty {
                    DisclosureGroup("Details", isExpanded: $showLog) {
                        ScrollView {
                            Text(log)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 115)
                        .background(Ink.editor, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 510)
        .background(Ink.header)
    }

    private var packageControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let suggestedFile {
                Button {
                    Task { candidates = await manager.findPackages(for: suggestedFile) }
                } label: {
                    Label("Find the package for \(suggestedFile)", systemImage: "magnifyingglass")
                }
                .disabled(manager.activity != nil)

                if let candidates {
                    if candidates.isEmpty {
                        Text("No TeX Live package contains this file. Check whether it belongs to your project.")
                            .font(.system(size: 11)).foregroundStyle(Ink.muted)
                    } else {
                        ForEach(candidates.prefix(10), id: \.self) { name in
                            Button("Install \(name)") {
                                Task { await manager.installPackage(name) }
                            }
                            .disabled(manager.activity != nil)
                        }
                    }
                }
            }
            HStack {
                TextField("Package name", text: $requestedPackage)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("TeX Live package name")
                Button("Install") {
                    let name = requestedPackage.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await manager.installPackage(name) }
                }
                .disabled(manager.activity != nil || !TeXInstallation.validName(requestedPackage.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}
