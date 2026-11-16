import Foundation
import PDFKit
import Testing
import TypewriterCore

@Test func wordRoundTrip() throws {
    let source = "A café ☕️\n\n  Second page.\n日本語\n"
    let bytes = try DocumentKind.word.write(source)
    #expect(bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]))
    #expect(try DocumentKind.word.read(bytes) == source)
}

@Test func opensUnicodeSourceFiles() throws {
    let text = "Montréal, Québec\nsecond line"
    let windows = text.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(try DocumentKind.latex.read(Data([0xEF, 0xBB, 0xBF]) + Data(windows.utf8)) == text)
    #expect(try DocumentKind.text.read(try #require(windows.data(using: .utf16))) == text)
    #expect(throws: CocoaError.self) { try DocumentKind.text.read(Data([0xFA, 0xBB])) }
}

@Test func textPreviewPaginatesWithoutDroppingTheEnd() throws {
    let lines = (1...240).map { "Line \($0) • A sentence for checking pagination." }
    let original = lines.joined(separator: "\n")
    let document = try #require(PDFDocument(data: try PrintLayout.pdf(for: original)))
    #expect(document.pageCount > 1)
    let content = try #require(document.string)
    let recovered = content.components(separatedBy: "•").count - 1
    #expect(recovered == lines.count)
    #expect(content.contains("Line 1 •"))
    #expect(content.contains("Line 240 •"))
    let blank = try #require(PDFDocument(data: try PrintLayout.pdf(for: "")))
    #expect(blank.pageCount == 1)
}

private let texRoot = ProcessInfo.processInfo.environment["TYPEWRITER_TEST_TEX"].map { URL(fileURLWithPath: $0) }

@Test func missingEngineProvidesSetupInstructions() async {
    let compiler = LatexCompiler(bundledRoot: nil, systemExecutable: nil)
    do {
        _ = try await compiler.compile(WritingTemplates.latex, documentURL: nil)
        Issue.record("Compilation unexpectedly succeeded without an engine")
    } catch let failure as LatexFailure {
        #expect(failure.reason == "Install LaTeX to compile.")
        #expect(failure.log.contains("LaTeX Dependencies"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test(.enabled(if: texRoot != nil))
func embeddedCompilerBuildsTheStarterWithoutSystemTeX() async throws {
    let compiler = LatexCompiler(bundledRoot: texRoot, systemExecutable: nil)
    let result = try await compiler.compile(WritingTemplates.latex, documentURL: nil)
    #expect(result.engine == "pdfLaTeX")
    #expect(result.passes == 1)
    let pdf = try #require(PDFDocument(data: result.pdf))
    #expect(pdf.pageCount == 1)
    #expect(pdf.string?.contains("The First Page") == true)
}

@Test(.enabled(if: texRoot != nil))
func embeddedCompilerResolvesLocalAssetsAndReferences() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Test Notebook \(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let chapters = root.appendingPathComponent("chapters")
    try FileManager.default.createDirectory(at: chapters, withIntermediateDirectories: false)
    let linked = #"\section{The project}\label{first} Text from the included file."#
    try Data(linked.utf8).write(to: chapters.appendingPathComponent("chapter.tex"))
    var image = try PrintLayout.pdf(for: "A PDF illustration")
    try image.write(to: root.appendingPathComponent("figure.pdf"))
    let source = #"""
    \documentclass{article}
    \usepackage{graphicx}
    \usepackage{amsmath,booktabs,hyperref,siunitx}
    \begin{document}
    \include{chapters/chapter}
    \includegraphics[width=18mm]{figure}
    See section~\ref{first}.
    \end{document}
    """#
    let file = root.appendingPathComponent("Test Document.tex")
    image = Data("Original file preserved".utf8)
    try image.write(to: file)
    let compiler = LatexCompiler(bundledRoot: texRoot, systemExecutable: nil)
    let result = try await compiler.compile(source, documentURL: file)
    #expect(result.passes == 2)
    let pdf = try #require(PDFDocument(data: result.pdf))
    let content = try #require(pdf.string)
    #expect(content.contains("Text from the included file."))
    #expect(content.contains("See section 1."))
    #expect(try Data(contentsOf: file) == image)
}

@Test(.enabled(if: texRoot != nil))
func latexReportsTheSourceLineForInvalidInput() async throws {
    let compiler = LatexCompiler(bundledRoot: texRoot, systemExecutable: nil)
    let source = #"""
    \documentclass{article}
    \begin{document}
    \unknownCommand
    \end{document}
    """#
    do {
        _ = try await compiler.compile(source, documentURL: nil)
        Issue.record("Invalid source produced a PDF")
    } catch let error as LatexFailure {
        #expect(error.reason.contains("Line 3"))
        #expect(error.log.contains("Undefined control sequence"))
    }
}
