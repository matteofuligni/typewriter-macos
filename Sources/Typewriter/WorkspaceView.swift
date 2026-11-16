import AppKit
import SwiftUI
import TypewriterCore

enum Ink {
    static let nsHeader = NSColor(srgbRed: 0.973, green: 0.951, blue: 0.905, alpha: 1)
    static let nsEditor = NSColor(srgbRed: 0.992, green: 0.980, blue: 0.945, alpha: 1)
    static let nsGutter = NSColor(srgbRed: 0.970, green: 0.951, blue: 0.902, alpha: 1)
    static let nsLine = NSColor(srgbRed: 0.884, green: 0.853, blue: 0.782, alpha: 1)
    static let nsCopper = NSColor(srgbRed: 0.585, green: 0.270, blue: 0.170, alpha: 1)
    static let nsText = NSColor(srgbRed: 0.17, green: 0.20, blue: 0.17, alpha: 1)
    static let nsMuted = NSColor(srgbRed: 0.46, green: 0.42, blue: 0.35, alpha: 1)
    static let nsGraphite = NSColor(srgbRed: 0.39, green: 0.43, blue: 0.30, alpha: 1)
    static let nsPreview = NSColor(srgbRed: 0.113, green: 0.168, blue: 0.144, alpha: 1)
    static let header = Color(nsColor: nsHeader)
    static let editor = Color(nsColor: nsEditor)
    static let gutter = Color(nsColor: nsGutter)
    static let line = Color(nsColor: nsLine)
    static let copper = Color(nsColor: nsCopper)
    static let text = Color(nsColor: nsText)
    static let muted = Color(nsColor: nsMuted)
    static let forest = Color(red: 0.13, green: 0.19, blue: 0.16)
    static let forestEdge = Color(red: 0.10, green: 0.15, blue: 0.13)
    static let onForest = Color(red: 0.94, green: 0.92, blue: 0.84)
    static let onForestMuted = Color(red: 0.72, green: 0.75, blue: 0.66)
    static let footer = Color(red: 0.941, green: 0.911, blue: 0.851)
}

struct WorkspaceView: View {
    let model: WorkspaceModel

    @AppStorage("workspaceSplit") private var split = 0.49
    @State private var dragging = false
    @State private var hovering = false
    @State private var showLog = false
    @State private var showSounds = false
    @State private var preview = PreviewControls()
    private let sounds = SoundBank.shared
    private let tex = TeXManager.shared

    private var isLatex: Bool { model.kind == .latex }
    private var focus: Bool { model.typewriterMode }
    private var shouldOfferSetup: Bool { isLatex && !focus && !tex.isChecking && tex.startupFailure != nil }
    private var canExport: Bool {
        if case .ready = model.status { return model.pdf != nil }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            titleRail
            if !focus { toolbar }
            Rectangle().fill(Ink.line).frame(height: 1)
            workspace
            if !focus {
                Rectangle().fill(Ink.line).frame(height: 1)
                statusBar
            }
        }
        .background(Ink.header)
        .foregroundStyle(Ink.text)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showLog) { diagnostics }
        .sheet(isPresented: Bindable(model).showsDependencies) {
            TeXDependenciesView(suggestedFile: model.missingPackageFile ?? tex.startupFailure?.missingPackageFile) {
                model.showsDependencies = false
            }
        }
        .onChange(of: shouldOfferSetup, initial: true) { _, needed in
            if needed, tex.claimSetupPrompt() { model.showsDependencies = true }
        }
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let sidebar = !focus && isLatex && model.showsNavigator
            let sidebarWidth: CGFloat = sidebar ? 209 : 0
            let material = max(1, geometry.size.width - sidebarWidth - 16)
            let editorWidth = focus ? min(742, geometry.size.width - 54) : max(295, min(material - 330, material * split))
            HStack(spacing: 0) {
                if sidebar {
                    ProjectNavigator(model: model).frame(width: 208)
                    Rectangle().fill(Ink.line).frame(width: 1)
                }
                if focus { Spacer(minLength: 0) }
                sourcePane
                    .frame(width: editorWidth)
                    .overlay {
                        if focus { Rectangle().strokeBorder(Ink.line).allowsHitTesting(false) }
                    }
                    .shadow(color: .black.opacity(focus ? 0.09 : 0), radius: 16, x: 0, y: 5)
                    .padding(.vertical, focus ? 16 : 0)
                if focus {
                    Spacer(minLength: 0)
                } else {
                    splitHandle(material: material, sidebarWidth: sidebarWidth)
                    previewPane.frame(maxWidth: .infinity)
                }
            }
            .coordinateSpace(name: "typewriter-workbench")
            .background(focus ? Ink.footer : Ink.editor)
        }
    }

    private var titleRail: some View {
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: "doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.muted)
                Text(model.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.dirty {
                    Circle().fill(Ink.copper).frame(width: 5, height: 5)
                        .accessibilityLabel("Unsaved changes")
                }
            }
            .frame(maxWidth: 350)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 33)
        .background(WindowDragArea())
        .padding(.horizontal, 86)
        .overlay(alignment: .trailing) {
            if focus {
                Button {
                    model.toggleTypewriterMode()
                } label: {
                    Label("Exit Typewriter Mode", systemImage: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .help("Return to the workspace (Esc)")
                .padding(.trailing, 19)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Ink.forest)
                    TypewriterGlyph()
                        .frame(width: 24, height: 24)
                }
                .frame(width: 39, height: 39)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Typewriter")
                        .font(.custom("Baskerville", size: 31, relativeTo: .title))
                        .tracking(-0.8)
                        .lineLimit(1)
                        .fixedSize()
                    Text("WRITING STUDIO")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(Ink.copper)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 13)
            Menu {
                Button("New LaTeX Document", action: { NSApp.sendAction(#selector(ApplicationDelegate.newLatex(_:)), to: NSApp.delegate, from: nil) })
                Button("New Word Document", action: { NSApp.sendAction(#selector(ApplicationDelegate.newWord(_:)), to: NSApp.delegate, from: nil) })
                Button("New Plain Text Document", action: { NSApp.sendAction(#selector(ApplicationDelegate.newText(_:)), to: NSApp.delegate, from: nil) })
            } label: {
                Label("New", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 71, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.trailing, 7)
            if isLatex {
                ToolButton("Dependencies", icon: "shippingbox", hint: "Manage the LaTeX engine and packages") {
                    model.showsDependencies = true
                }
            }
            ToolButton("Open", icon: "folder", hint: "Open document (⌘O)") {
                NSDocumentController.shared.openDocument(nil)
            }
            ToolButton("Save", icon: "square.and.arrow.down", hint: "Save document (⌘S)") {
                model.document?.saveFromToolbar()
            }
            ToolButton("Typewriter Mode", icon: "text.cursor", hint: "Enter Typewriter Mode (⇧⌘T)") {
                model.toggleTypewriterMode()
            }
            Rectangle().fill(Ink.line).frame(width: 1, height: 23)
                .padding(.horizontal, 2)
            ToolButton("Export PDF", icon: "arrow.up.right", hint: "Export PDF (⇧⌘E)", primary: true) {
                model.document?.exportPDF()
            }
            .disabled(!canExport)
        }
        .padding(.horizontal, 24)
        .padding(.top, 7)
        .padding(.bottom, 13)
    }

    private var sourcePane: some View {
        VStack(spacing: 0) {
            if !focus { sourceHeader }
            ZStack {
                let inspected = model.inspectedFile
                SourceEditor(model: model, loadedRevision: model.loadedRevision, isLatex: isLatex,
                             navigation: model.navigation, carriageMode: focus)
                    .opacity(inspected == nil ? 1 : 0)
                    .allowsHitTesting(inspected == nil)
                    .accessibilityHidden(inspected != nil)
                if let file = inspected {
                    SourceEditor(model: model, loadedRevision: 0, isLatex: true, file: file, navigation: model.navigation)
                        .id(file.id)
                }
            }
            .background(Ink.editor)
        }
        .background(Ink.editor)
    }

    private var sourceHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                if isLatex {
                    Button {
                        model.showsNavigator.toggle()
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(model.showsNavigator ? Ink.copper : Ink.muted)
                            .frame(width: 23, height: 23)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.showsNavigator ? "Hide navigator" : "Show navigator")
                    .help("Project files and outline")
                }
                let inspected = model.inspectedFile
                paneTitle(inspected?.url?.lastPathComponent ?? (isLatex ? "Source" : "Text"), dark: false)
                Spacer()
                if inspected != nil {
                    Button {
                        model.document?.openLinkedFile()
                    } label: {
                        Label("Edit", systemImage: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.copper)
                    .help("Open the linked file in a separate window to edit it")
                } else {
                    Text(".\(model.kind.fileExtension)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(Ink.copper)
                        .background(Ink.copper.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Format \(model.kind.label)")
                }
            }
            .padding(.horizontal, 19)
            .frame(height: 47)
            .background(Ink.editor)
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    private func splitHandle(material: CGFloat, sidebarWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Ink.forestEdge)
            .frame(width: 16)
            .frame(maxHeight: .infinity)
            .overlay {
                VStack(spacing: 4) {
                    ForEach(0..<3) { _ in
                        Circle().fill(dragging || hovering ? Ink.onForest : Ink.onForestMuted.opacity(0.6))
                            .frame(width: 3, height: 3)
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { over in
                hovering = over
                if over { NSCursor.resizeLeftRight.set() } else if !dragging { NSCursor.arrow.set() }
            }
            .onTapGesture(count: 2) { split = 0.49 }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("typewriter-workbench"))
                .onChanged { value in
                    dragging = true
                    NSCursor.resizeLeftRight.set()
                    split = max(295 / material, min(1 - 330 / material, (value.location.x - sidebarWidth - 8) / material))
                }
                .onEnded { _ in
                    dragging = false
                    if !hovering { NSCursor.arrow.set() }
                })
            .accessibilityLabel("Divider between editor and preview")
            .accessibilityValue("\(Int(split * 100)) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: split = min(1 - 330 / material, split + 0.04)
                case .decrement: split = max(295 / material, split - 0.04)
                @unknown default: break
                }
            }
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                paneTitle("Preview", dark: true)
                Spacer(minLength: 6)
                if isLatex {
                    Button {
                        model.compileNow()
                    } label: {
                        Label("Compile", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 25)
                    }
                    .buttonStyle(InkButtonStyle(
                        foreground: Ink.onForest, fill: .white.opacity(0.07), stroke: .white.opacity(0.16)
                    ))
                    .help("Compile LaTeX source (⌘R)")
                    .disabled(tex.isInstalling || !tex.isAvailable)
                } else {
                    Text("PDF")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Ink.onForestMuted)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 47)
            .background(Ink.forest)
            Rectangle().fill(Ink.onForest.opacity(0.12)).frame(height: 1)
            ZStack {
                LinearGradient(colors: [Ink.forest, Ink.forestEdge], startPoint: .topLeading, endPoint: .bottomTrailing)
                Pattern().accessibilityHidden(true)
                if let data = model.pdf {
                    PDFSurface(data: data, revision: model.pdfRevision, controls: preview)
                        .aspectRatio(preview.fitted ? preview.aspect : nil, contentMode: .fit)
                        .shadow(color: .black.opacity(preview.fitted ? 0.38 : 0), radius: 12, x: 0, y: 5)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                } else {
                    previewPlaceholder
                }
            }
            Rectangle().fill(Ink.onForest.opacity(0.12)).frame(height: 1)
            pdfControls
        }
        .background(Ink.forest)
        .coordinateSpace(name: "preview")
    }

    private var previewPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 31, weight: .ultraLight))
            Text("PDF Preview")
                .font(.custom("Baskerville", size: 24))
                .foregroundStyle(Ink.onForest)
            if isLatex && !tex.isAvailable {
                Button("Install TeX Live") { model.showsDependencies = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Ink.copper)
                    .disabled(tex.isInstalling)
            } else if case .failed = model.status {
                Button("Show Compilation Error") { showLog = true }
                    .buttonStyle(.link)
                    .foregroundStyle(Ink.onForest)
            } else {
                Text(isLatex ? "Compile the source to see the PDF." : "Your typeset text will appear here.")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(Ink.onForestMuted)
        .multilineTextAlignment(.center)
        .padding(16)
    }

    private var pdfControls: some View {
        HStack(spacing: 5) {
            PreviewButton(icon: "chevron.left", label: "Previous page") { preview.go(-1) }
                .disabled(preview.page <= 1)
            Text(preview.total > 0 ? "\(preview.page) / \(preview.total)" : "—")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Ink.onForestMuted)
                .frame(minWidth: 35)
                .accessibilityLabel("Page \(preview.page) of \(preview.total)")
            PreviewButton(icon: "chevron.right", label: "Next page") { preview.go(1) }
                .disabled(preview.page >= preview.total)
            Spacer(minLength: 6)
            PreviewButton(icon: "minus", label: "Zoom out") { preview.zoom(-1) }
                .disabled(preview.total == 0)
            PreviewButton(icon: "rectangle.inset.filled", label: "Fit page") { preview.fit() }
                .disabled(preview.total == 0)
            PreviewButton(icon: "plus", label: "Zoom in") { preview.zoom(1) }
                .disabled(preview.total == 0)
        }
        .padding(.horizontal, 13)
        .frame(height: 32)
        .background(Ink.forest)
    }

    private var statusBar: some View {
        HStack(spacing: 11) {
            Text("Ln \(model.line) · Col \(model.column)")
                .monospacedDigit()
                .accessibilityLabel("Line \(model.line), column \(model.column)")
            Rectangle().fill(Ink.line).frame(width: 1, height: 12)
            Text(isLatex ? "UTF-8" : (model.words == 1 ? "1 word" : "\(model.words) words"))
            Spacer(minLength: 8)
            compileStatus
            Spacer(minLength: 8)
            if isLatex {
                Button {
                    model.automatic.toggle()
                } label: {
                    Label(model.automatic ? "Auto" : "Manual", systemImage: model.automatic ? "bolt.fill" : "hand.raised")
                        .foregroundStyle(model.automatic ? Ink.copper : Ink.muted)
                }
                .buttonStyle(.plain)
                .help(model.automatic ? "Turn auto-compile off" : "Turn auto-compile on")
            }
            Button {
                showSounds.toggle()
            } label: {
                Label(sounds.enabled ? sounds.preset.title : "Muted",
                      systemImage: sounds.enabled ? "speaker.wave.2" : "speaker.slash")
                    .foregroundStyle(sounds.enabled ? Ink.muted : Ink.copper)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Keystroke Sounds")
            .help("Choose or mute keystroke sounds")
            .popover(isPresented: $showSounds, arrowEdge: .bottom) { soundOptions }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(Ink.muted)
        .lineLimit(1)
        .padding(.horizontal, 17)
        .frame(height: 29)
        .background(Ink.footer)
    }

    @ViewBuilder private var compileStatus: some View {
        if isLatex && tex.isInstalling {
            Label("Installing LaTeX…", systemImage: "arrow.down.circle")
        } else {
            switch model.status {
            case .waiting:
                Label(isLatex && !model.automatic ? "Preview needs updating" : "Waiting", systemImage: "circle.dotted")
            case .rendering:
                Label(isLatex ? "Compilezione…" : "Typesetting…", systemImage: "clock")
            case .ready(let detail):
                Label(detail, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color(nsColor: Ink.nsGraphite))
                    .help("Preview is up to date")
            case .failed(let message):
                Button {
                    if isLatex && (!tex.isAvailable || model.missingPackageFile != nil) {
                        model.showsDependencies = true
                    } else {
                        showLog = true
                    }
                } label: {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Ink.copper)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Show compilation details")
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Compilation Details").font(.custom("Baskerville", size: 26))
            if case .failed(let message) = model.status { Text(message).font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.copper) }
            ScrollView {
                Text(model.log.isEmpty ? "No additional details." : model.log)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Ink.editor, in: RoundedRectangle(cornerRadius: 6))
            HStack {
                if let file = model.missingPackageFile {
                    Button("Package for \(file)") {
                        showLog = false
                        model.showsDependencies = true
                    }
                }
                if !model.log.isEmpty {
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.log, forType: .string)
                    }
                }
                Spacer()
                Button("Close") { showLog = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 610, height: 400)
        .background(Ink.header)
    }

    private var soundOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Keystroke Sounds", isOn: Bindable(sounds).enabled)
                .toggleStyle(.switch)
                .font(.system(size: 12, weight: .medium))
            Divider()
            ForEach(SoundPreset.allCases) { preset in
                Button {
                    sounds.select(preset)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: sounds.enabled && sounds.preset == preset ? "checkmark.circle.fill" : "play.circle")
                            .foregroundStyle(Ink.copper)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title).font(.system(size: 12, weight: .semibold))
                            Text(preset.description).font(.system(size: 11)).foregroundStyle(Ink.muted)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 250)
        .background(Ink.header)
    }

    private func paneTitle(_ title: String, dark: Bool) -> some View {
        Text(title)
            .font(.custom("Baskerville", size: 20))
            .foregroundStyle(dark ? Ink.onForest : Ink.text)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct TypewriterGlyph: View {
    var body: some View {
        Canvas { context, _ in
            var silhouette = Path()
            silhouette.move(to: CGPoint(x: 7.5, y: 11))
            silhouette.addLine(to: CGPoint(x: 7.5, y: 4))
            silhouette.addQuadCurve(to: CGPoint(x: 9, y: 2.5), control: CGPoint(x: 7.5, y: 2.5))
            silhouette.addLine(to: CGPoint(x: 15, y: 2.5))
            silhouette.addQuadCurve(to: CGPoint(x: 16.5, y: 4), control: CGPoint(x: 16.5, y: 2.5))
            silhouette.addLine(to: CGPoint(x: 16.5, y: 11))
            silhouette.move(to: CGPoint(x: 5, y: 11))
            silhouette.addLine(to: CGPoint(x: 19, y: 11))
            silhouette.addLine(to: CGPoint(x: 21.5, y: 18))
            silhouette.addQuadCurve(to: CGPoint(x: 19.5, y: 21), control: CGPoint(x: 22, y: 21))
            silhouette.addLine(to: CGPoint(x: 4.5, y: 21))
            silhouette.addQuadCurve(to: CGPoint(x: 2.5, y: 18), control: CGPoint(x: 2, y: 21))
            silhouette.closeSubpath()
            context.stroke(silhouette, with: .color(Ink.onForest), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

            var details = Path()
            for (x, y, width) in [(10.0, 6.0, 4.0), (10, 8.3, 2.5), (6.8, 14.8, 1), (9.8, 14.8, 1),
                                  (12.8, 14.8, 1), (15.8, 14.8, 1), (8, 18, 8)] {
                details.move(to: CGPoint(x: x, y: y))
                details.addLine(to: CGPoint(x: x + width, y: y))
            }
            context.stroke(details, with: .color(Ink.onForest), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }
}

private struct Pattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 12
            var dots = Path()
            for x in stride(from: CGFloat(7), to: size.width, by: spacing) {
                for y in stride(from: CGFloat(7), to: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            context.fill(dots, with: .color(Ink.onForest.opacity(0.15)))
        }
        .allowsHitTesting(false)
    }
}

struct InkButtonStyle: ButtonStyle {
    var foreground: Color
    var fill: Color
    var stroke: Color
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(fill.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.48)
    }
}

private struct ToolButton: View {
    let title: String
    let icon: String
    let hint: String
    var primary = false
    let action: () -> Void

    init(_ title: String, icon: String, hint: String, primary: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.hint = hint
        self.primary = primary
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 30)
        }
        .buttonStyle(InkButtonStyle(
            foreground: primary ? Ink.onForest : Ink.text,
            fill: primary ? Ink.forest : Ink.editor,
            stroke: primary ? Ink.forest : Ink.line
        ))
        .help(hint)
    }
}

private struct PreviewButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Ink.onForest.opacity(enabled ? 1 : 0.35))
                .frame(width: 25, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
