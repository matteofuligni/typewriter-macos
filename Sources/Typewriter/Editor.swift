import AppKit
import SwiftUI
import TypewriterCore

@MainActor
struct SourceEditor: NSViewRepresentable {
    let model: WorkspaceModel
    let loadedRevision: Int
    let isLatex: Bool
    var file: LatexProject.File? = nil
    let navigation: WorkspaceModel.Navigation?
    var carriageMode = false

    private var fileID: String { file?.id ?? LatexProject.rootID }

    func makeNSView(context: Context) -> EditorSurface {
        let editor = EditorSurface(model: model, fileID: fileID)
        editor.load(file?.source ?? model.source, revision: loadedRevision, latex: isLatex)
        editor.setCarriageMode(carriageMode)
        return editor
    }

    func updateNSView(_ editor: EditorSurface, context: Context) {
        let changed = editor.revision != loadedRevision || (file != nil && editor.textView.string != file?.source)
        if changed {
            editor.load(file?.source ?? model.source, revision: loadedRevision, latex: isLatex)
        }
        editor.setCarriageMode(carriageMode)
        if let navigation, navigation.fileID == fileID {
            editor.jump(to: navigation)
        }
    }
}

@MainActor
final class EditorSurface: NSView, NSTextViewDelegate {
    let textView: MechanicalTextView
    private let scroll = NSScrollView()
    private let gutter = LineGutter()
    private let manager = NSLayoutManager()
    private let storage = NSTextStorage()
    private let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    private weak var model: WorkspaceModel?
    private let fileID: String
    private var navigationID: UUID?
    private var starts = [0]
    private var latex = false
    private var loading = false
    private var refreshQueued = false
    private var styledRange = NSRange(location: 0, length: 0)
    private var styleInvalidated = true
    private var didSetFocus = false
    private var carriageMode = false
    private var needsCarriageFollow = false
    private var caretAnchor: CGFloat = 0
    private let trailingInset: CGFloat = 30
    private let rules: [(NSRegularExpression, NSColor)] = [
        (try! NSRegularExpression(pattern: #"\\(?:[A-Za-z@]+|[^ \r\n])"#), Ink.nsCopper),
        (try! NSRegularExpression(pattern: #"[{}\[\]&_^$]"#), Ink.nsGraphite),
        (try! NSRegularExpression(pattern: #"(?<!\\)%[^\r\n]*"#), NSColor(srgbRed: 0.35, green: 0.43, blue: 0.32, alpha: 1))
    ]
    private(set) var revision = -1

    init(model: WorkspaceModel, fileID: String) {
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        textView = MechanicalTextView(frame: .zero, textContainer: container)
        self.model = model
        self.fileID = fileID
        super.init(frame: .zero)

        wantsLayer = true
        clipsToBounds = true
        layer?.backgroundColor = Ink.nsEditor.cgColor
        setAccessibilityIdentifier("source-editor")
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.scrollerStyle = .overlay
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.documentView = textView
        addSubview(scroll)
        gutter.owner = self
        gutter.clipsToBounds = true
        gutter.setAccessibilityHidden(true)
        addSubview(gutter)

        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        textView.delegate = self
        textView.exitCarriageMode = { [weak model] in
            guard let model, model.typewriterMode else { return false }
            model.toggleTypewriterMode()
            return true
        }
        textView.allowsUndo = true
        textView.isEditable = fileID == LatexProject.rootID
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: trailingInset, height: 25)
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.insertionPointColor = Ink.nsCopper
        textView.selectedTextAttributes = [.backgroundColor: Ink.nsCopper.withAlphaComponent(0.19), .foregroundColor: Ink.nsText]
        textView.wantsLayer = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView
        )
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didSetFocus, fileID == LatexProject.rootID else { return }
        didSetFocus = true
        window.initialFirstResponder = textView
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self.textView)
        }
    }

    override func layout() {
        super.layout()
        let gutterWidth: CGFloat = latex && !carriageMode ? 48 : 0
        gutter.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        let scrollWidth = max(0, bounds.width - gutterWidth)
        scroll.frame = NSRect(x: gutterWidth, y: 0, width: scrollWidth, height: bounds.height)
        let height = scroll.contentSize.height
        let bottomMargin = min(96, max(34, height * 0.12))
        let anchor = carriageMode ? max(0, height - bottomMargin) : 0
        let inset = NSSize(width: carriageMode ? 60 : trailingInset, height: carriageMode ? max(0, anchor - 10) : 25)
        if textView.textContainerInset != inset || caretAnchor != anchor {
            caretAnchor = anchor
            textView.textContainerInset = inset
            queueCarriageFollow()
        }
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        if textView.frame.width != scroll.contentSize.width {
            textView.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(textView.frame.height, scroll.contentSize.height)))
        }
        queueRefresh()
    }

    func setCarriageMode(_ enabled: Bool) {
        guard enabled != carriageMode else { return }
        carriageMode = enabled
        gutter.isHidden = !latex || enabled
        scroll.hasVerticalScroller = !enabled
        needsLayout = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.carriageMode == enabled else { return }
            self.layoutSubtreeIfNeeded()
            self.window?.makeFirstResponder(self.textView)
            if enabled {
                self.followCaret()
            } else {
                self.textView.scrollRangeToVisible(self.textView.selectedRange())
            }
        }
    }

    private func queueCarriageFollow() {
        guard carriageMode, !needsCarriageFollow else { return }
        needsCarriageFollow = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.needsCarriageFollow = false
            self.followCaret()
        }
    }

    private func followCaret() {
        guard carriageMode, caretAnchor > 0 else { return }
        let offset = min(textView.selectedRange().location, storage.length)
        guard let fragment = lineFragment(at: offset) else { return }
        let clip = scroll.contentView
        var proposed = clip.bounds
        proposed.origin.y = max(0, textView.textContainerOrigin.y + fragment.midY - caretAnchor)
        let point = clip.constrainBoundsRect(proposed).origin
        if abs(point.y - clip.bounds.minY) > 0.5 {
            clip.scroll(to: point)
            scroll.reflectScrolledClipView(clip)
        }
    }

    func load(_ source: String, revision: Int, latex: Bool) {
        loading = true
        self.revision = revision
        self.latex = latex
        gutter.isHidden = !latex || carriageMode
        if fileID != LatexProject.rootID {
            textView.setAccessibilityLabel("Linked source, read-only")
        } else {
            textView.setAccessibilityLabel(latex ? "LaTeX source" : "Document text")
        }
        textView.string = source
        textView.textColor = Ink.nsText
        textView.font = latex ? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            : (NSFont(name: "AmericanTypewriter", size: 16) ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = latex ? 4 : 7
        paragraph.defaultTabInterval = latex ? 31 : 40
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.isContinuousSpellCheckingEnabled = !latex
        textView.placeholder = latex ? nil : "Start writing…"
        storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scroll.contentView.scroll(to: .zero)
        starts = Self.lineStarts(source)
        styleInvalidated = true
        needsLayout = true
        loading = false
        selection()
        queueRefresh()
        queueCarriageFollow()
    }

    func jump(to navigation: WorkspaceModel.Navigation) {
        guard navigationID != navigation.id else { return }
        navigationID = navigation.id
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model?.navigation == navigation else { return }
            let row = min(self.starts.count - 1, max(0, navigation.line - 1))
            let range = NSRange(location: self.starts[row], length: 0)
            self.window?.makeFirstResponder(self.textView)
            self.textView.setSelectedRange(range)
            self.textView.scrollRangeToVisible(range)
            self.selection()
            self.queueRefresh()
            self.queueCarriageFollow()
        }
    }

    private static func lineStarts(_ source: String) -> [Int] {
        var starts = [0]
        for (offset, char) in source.utf16.enumerated() where char == 10 {
            starts.append(offset + 1)
        }
        return starts
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        fileID == LatexProject.rootID ? model?.document?.undoManager : nil
    }

    func textDidChange(_ notification: Notification) {
        guard !loading, fileID == LatexProject.rootID else { return }
        let source = textView.string
        starts = Self.lineStarts(source)
        model?.edited(source)
        styleInvalidated = true
        selection()
        queueRefresh()
        queueCarriageFollow()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !loading {
            selection()
            queueRefresh()
            queueCarriageFollow()
        }
    }

    private func selection() {
        guard model?.inspectedFileID == fileID else { return }
        let offset = min(textView.selectedRange().location, storage.length)
        let row = rowIndex(at: offset)
        model?.line = row + 1
        let size = max(0, offset - starts[row])
        let preceding = (textView.string as NSString).substring(with: NSRange(location: starts[row], length: size))
        model?.column = preceding.count + 1
    }

    private func rowIndex(at position: Int) -> Int {
        var low = 0
        var high = starts.count
        while low + 1 < high {
            let mid = low + (high - low) / 2
            if starts[mid] <= position { low = mid } else { high = mid }
        }
        return low
    }

    @objc private func scrolled() { queueRefresh() }

    private func queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.refresh()
        }
    }

    private func refresh() {
        guard textView.frame.width > 1 else { return }
        gutter.needsDisplay = true
        textView.needsDisplay = true
        let visible = scroll.contentView.bounds.offsetBy(dx: -textView.textContainerOrigin.x, dy: -textView.textContainerOrigin.y)
        updateLineHighlight(in: visible)
        guard latex, storage.length > 0 else { return }
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        if !styleInvalidated,
           NSLocationInRange(characters.location, styledRange),
           NSMaxRange(characters) <= NSMaxRange(styledRange) { return }
        let string = textView.string
        let ns = string as NSString
        let from = max(0, characters.location - 1200)
        let to = min(storage.length, NSMaxRange(characters) + 1200)
        let range = ns.lineRange(for: NSRange(location: from, length: max(0, to - from)))
        let prior = NSIntersectionRange(styledRange, NSRange(location: 0, length: storage.length))
        if prior.length > 0 { manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: prior) }
        manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        for (rule, color) in rules {
            rule.enumerateMatches(in: string, range: range) { [manager] match, _, _ in
                if let match { manager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: match.range) }
            }
        }
        styledRange = range
        styleInvalidated = false
    }

    private func updateLineHighlight(in visible: CGRect) {
        textView.highlightedLine = nil
        guard latex, !carriageMode else { return }
        let offset = textView.selectedRange().location
        // Avoid laying out an offscreen insertion point when the user scrolls elsewhere.
        let glyphRange = manager.glyphRange(forBoundingRect: visible, in: container)
        let range = manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard offset >= range.location, offset <= NSMaxRange(range) else { return }
        guard let fragment = lineFragment(at: offset), fragment.height > 0 else { return }
        textView.highlightedLine = CGRect(
            x: 11, y: textView.textContainerOrigin.y + fragment.minY,
            width: max(0, textView.bounds.width - 22), height: fragment.height
        )
    }

    private func lineFragment(at offset: Int) -> CGRect? {
        if offset == storage.length {
            if offset > 0 {
                manager.ensureLayout(forCharacterRange: NSRange(location: offset - 1, length: 1))
            } else {
                manager.ensureLayout(for: container)
            }
            if manager.extraLineFragmentTextContainer === container { return manager.extraLineFragmentRect }
        }
        guard storage.length > 0 else { return nil }
        let glyph = manager.glyphIndexForCharacter(at: min(offset, storage.length - 1))
        return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    func drawGutter() {
        let viewport = scroll.contentView.bounds
        let origin = textView.textContainerOrigin
        let area = viewport.offsetBy(dx: -origin.x, dy: -origin.y)
        let visible = manager.glyphRange(forBoundingRect: area, in: container)
        let active = model.map { $0.line - 1 } ?? 0
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        func draw(_ row: Int, _ fragment: CGRect) {
            let y = fragment.minY + origin.y - viewport.minY
            guard y < gutter.bounds.height, y + fragment.height > 0 else { return }
            let value = NSAttributedString(string: "\(row + 1)", attributes: [
                .font: font, .foregroundColor: row == active ? Ink.nsCopper : Ink.nsMuted
            ])
            let size = value.size()
            value.draw(at: NSPoint(x: gutter.bounds.width - 11 - size.width, y: y + max(0, (fragment.height - size.height) * 0.5)))
        }
        manager.enumerateLineFragments(forGlyphRange: visible) { fragment, _, _, glyphs, _ in
            let position = self.manager.characterIndexForGlyph(at: glyphs.location)
            let row = self.rowIndex(at: position)
            if self.starts[row] == position { draw(row, fragment) }
        }
        if manager.extraLineFragmentTextContainer != nil, starts.last == storage.length {
            draw(starts.count - 1, manager.extraLineFragmentRect)
        }
    }
}

@MainActor private final class LineGutter: NSView {
    weak var owner: EditorSurface?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Ink.nsGutter.setFill()
        bounds.intersection(dirtyRect).fill()
        Ink.nsLine.setFill()
        CGRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        owner?.drawGutter()
    }
}

@MainActor
final class MechanicalTextView: NSTextView {
    var placeholder: String?
    var highlightedLine: NSRect?
    var exitCarriageMode: (() -> Bool)?

    override func cancelOperation(_ sender: Any?) {
        if exitCarriageMode?() != true { super.cancelOperation(sender) }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let highlightedLine, highlightedLine.intersects(dirtyRect) {
            Ink.nsCopper.withAlphaComponent(0.075).setFill()
            NSBezierPath(roundedRect: highlightedLine, xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
        if let placeholder, string.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: Ink.nsMuted
            ]
            (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: attributes)
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard flag else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: false)
            return
        }
        color.setFill()
        let flipped = isFlipped
        let base = flipped ? rect.maxY - 4 : rect.minY + 2
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: base, width: 9, height: 2), xRadius: 1, yRadius: 1).fill()
    }

    private func play(_ stroke: SoundBank.Stroke) {
        if isEditable { SoundBank.shared.play(stroke) }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        play(.letter)
    }

    override func insertNewline(_ sender: Any?) {
        super.insertNewline(sender)
        play(.carriage)
    }

    override func insertTab(_ sender: Any?) {
        super.insertTab(sender)
        play(.letter)
    }

    override func deleteBackward(_ sender: Any?) {
        let wasEmpty = selectedRange().location == 0 && selectedRange().length == 0
        super.deleteBackward(sender)
        if !wasEmpty { play(.backspace) }
    }

    override func deleteForward(_ sender: Any?) {
        let atEnd = selectedRange().location >= (string as NSString).length
        super.deleteForward(sender)
        if !atEnd { play(.backspace) }
    }
}
