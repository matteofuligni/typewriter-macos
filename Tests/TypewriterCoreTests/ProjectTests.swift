import Foundation
import Testing
@testable import TypewriterCore

@Test func latexProjectFollowsIncludesInPlaceAndSkipsLiteralExamples() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Typewriter Outline \(UUID())")
    let chapters = directory.appendingPathComponent("Book Sections")
    try FileManager.default.createDirectory(at: chapters, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let child = #"""
    \chapter[Methods]{The \textbf{methods}}
    \subimport{}{variant}
    \include{main}
    """#
    try Data(child.utf8).write(to: chapters.appendingPathComponent("methods.tex"))
    try Data(#"\section*{Procedure {A}}"#.utf8).write(to: chapters.appendingPathComponent("variant.tex"))

    let source = #"""
    \chapter {Introduction}
    % \chapter{Comment}
    \begin{verbatim}
    \section{Example}
    \end{verbatim}
    \verb|\section{Another example}|
    \input{Book Sections/methods}
    \include{missing}
    \chapter{Results}
    \end{document}
    \chapter{After the document}
    """#
    let root = directory.appendingPathComponent("main.tex")
    try Data(source.utf8).write(to: root)
    let outline = LatexProject.index(source: source, root: root)
    #expect(outline.files.map(\.name) == ["main.tex", "Book Sections/methods.tex", "Book Sections/variant.tex"])
    #expect(outline.files.map(\.depth) == [0, 1, 2])
    #expect(outline.headings.map(\.title) == ["Introduction", "Methods", "Procedure {A}", "Results"])
    #expect(outline.headings.map(\.line) == [1, 1, 1, 9])
    #expect(outline.headings[2].fileID == outline.files[2].id)
    #expect(outline.unresolved == ["missing"])
}

@Test func identifiesPackagesByTheExactFilename() {
    let output = """
    tlmgr: package repository CTAN (verified)
    unusual-name:
        texmf-dist/tex/latex/unusual/module.sty
        texmf-dist/tex/latex/unusual/module.tex
    look-alike:
        texmf-dist/tex/latex/look-alike/mymodule.sty
    """
    #expect(TeXInstallation.packageNames(in: output, matching: "module.sty") == ["unusual-name"])
    #expect(!TeXInstallation.validName("--repository"))
    #expect(!TeXInstallation.validName("../package"))
    let error = LatexFailure("Missing package", log: "! LaTeX Error: File \u{60}module.sty' not found.")
    #expect(error.missingPackageFile == "module.sty")
    #expect(LatexFailure("", log: "! LaTeX Error: File \u{60}chapter.tex' not found.").missingPackageFile == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TYPEWRITER_TEST_NETWORK_INSTALL"] == "1"))
func installsTeXLiveAndAnExtraPackageFromCTAN() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Typewriter TeX Check \(UUID())")
    let installation = TeXInstallation(directory: directory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await installation.install { print($0) }
    let engine = try #require(installation.executable)
    let packages = try await installation.packages(containing: "kantlipsum.sty")
    #expect(packages.contains("kantlipsum"))
    try await installation.installPackage("kantlipsum")
    let source = #"""
    \documentclass{article}
    \usepackage{kantlipsum}
    \begin{document}
    The test succeeded. \kant[1]
    \end{document}
    """#
    let compiler = LatexCompiler(bundledRoot: nil, systemExecutable: nil, managedExecutable: engine)
    let result = try await compiler.compile(source, documentURL: nil)
    #expect(result.pdf.starts(with: Data("%PDF".utf8)))
}
