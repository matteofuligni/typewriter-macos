import AppKit
import CoreText
import UniformTypeIdentifiers

public enum DocumentKind: String, CaseIterable, Sendable {
    case latex = "org.tug.tex"
    case word = "org.openxmlformats.wordprocessingml.document"
    case text = "public.plain-text"

    public var fileExtension: String {
        switch self {
        case .latex: "tex"
        case .word: "docx"
        case .text: "txt"
        }
    }

    public var label: String {
        switch self {
        case .latex: "LaTeX"
        case .word: "Word"
        case .text: "Text"
        }
    }

    public static func kind(for identifier: String) -> Self? {
        if let exact = Self(rawValue: identifier) { return exact }
        guard let type = UTType(identifier) else { return nil }
        if type.preferredFilenameExtension == "tex" { return .latex }
        if type.preferredFilenameExtension == "docx" { return .word }
        return type.conforms(to: .plainText) ? .text : nil
    }

    public func read(_ data: Data) throws -> String {
        if self == .word {
            let imported = try NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil
            )
            return imported.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        }
        let declaredUTF16 = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        guard let decoded = String(data: data, encoding: declaredUTF16 ? .utf16 : .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return String(decoded.dropFirst(decoded.hasPrefix("\u{FEFF}") ? 1 : 0))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    public func write(_ source: String) throws -> Data {
        if self == .word { return try PrintLayout.wordData(for: source) }
        return Data(source.utf8)
    }
}

public enum PrintLayout {
    public static let pageSize = CGSize(width: 595.28, height: 841.89)
    public static let margin: CGFloat = 66

    private static func typeset(_ source: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4
        return NSAttributedString(
            string: source,
            attributes: [
                .font: NSFont(name: "Times New Roman", size: 12) ?? NSFont(name: "Times-Roman", size: 12)!,
                .foregroundColor: NSColor(white: 0.08, alpha: 1),
                .paragraphStyle: paragraph
            ]
        )
    }

    static func wordData(for source: String) throws -> Data {
        let text = typeset(source)
        return try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [
            .documentType: NSAttributedString.DocumentType.officeOpenXML,
            .paperSize: NSValue(size: pageSize),
            .leftMargin: margin, .rightMargin: margin, .topMargin: margin, .bottomMargin: margin
        ])
    }

    public static func pdf(for source: String) throws -> Data {
        let bytes = NSMutableData()
        var page = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: bytes), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var closed = false
        defer { if !closed { context.closePDF() } }
        let text = typeset(source)
        let setter = CTFramesetterCreateWithAttributedString(text)
        let printable = page.insetBy(dx: margin, dy: margin)
        let path = CGPath(rect: printable, transform: nil)
        var offset = 0
        repeat {
            try Task.checkCancellation()
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else {
                if text.length == 0 { break }
                throw CocoaError(.fileWriteUnknown)
            }
            offset += visible.length
        } while offset < text.length
        context.closePDF()
        closed = true
        return bytes as Data
    }
}

public enum WritingTemplates {
    public static let latex = #"""
    \documentclass[11pt,a4paper]{article}
    \usepackage[T1]{fontenc}
    \usepackage[english]{babel}
    \usepackage[margin=27mm]{geometry}
    \usepackage{lmodern}
    \usepackage{xcolor}

    \definecolor{ink}{HTML}{26352F}
    \definecolor{copper}{HTML}{994F33}
    \setlength{\parindent}{0pt}
    \setlength{\parskip}{0.8em}

    \begin{document}
    \pagestyle{empty}
    \color{ink}

    {\small\textcolor{copper}{\textsc{Writing Notebook}}}

    \vspace{1.4em}
    {\Huge\bfseries The First Page\par}
    \vspace{0.5em}
    {\large\itshape Every draft starts with a keystroke.\par}

    \vspace{1.2em}
    {\color{copper}\rule{0.16\linewidth}{0.5pt}}
    \vspace{0.8em}

    \section*{Room to Write}
    Write in the editor on the left. The preview on the right
    shows the page you can export, print, or share.

    \section*{Try LaTeX}
    You can add equations, tables, figures, and references.
    Here is the Pythagorean theorem:
    \[
        a^2 + b^2 = c^2
    \]

    \end{document}

    """#
}
