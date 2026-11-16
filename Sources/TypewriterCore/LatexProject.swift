import Foundation

public struct LatexProject: Sendable {
    public static let rootID = "root"

    public struct File: Identifiable, Sendable {
        public let id: String
        public let url: URL?
        public let name: String
        public let source: String
        public let depth: Int
    }

    public struct Heading: Identifiable, Sendable {
        public var id: String { "\(fileID):\(offset)" }
        public let fileID: String
        public let line: Int
        public let offset: Int
        public let level: Int
        public let command: String
        public let title: String
    }

    public var files: [File] = []
    public var headings: [Heading] = []
    public var unresolved: [String] = []

    public init() {}

    public static func index(source: String, root: URL?) -> Self {
        var index = Self()
        let base = root?.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let root = root?.resolvingSymlinksInPath().standardizedFileURL
        var visited: Set<URL> = Set(root.map { [$0] } ?? [])

        func walk(_ file: File) {
            guard !Task.isCancelled else { return }
            index.files.append(file)
            var scanner = LatexOutlineScanner(file.source)
            while !Task.isCancelled, let item = scanner.next() {
                switch item {
                case .heading(let command, let level, let title, let line, let offset):
                    index.headings.append(Heading(fileID: file.id, line: line, offset: offset, level: level, command: command, title: title))
                case .include(let path, let relativeToParent):
                    guard let base else { continue }
                    let parent = file.url?.deletingLastPathComponent() ?? base
                    let locations = relativeToParent ? [parent, base] : [base, parent]
                    guard let child = locations.lazy.compactMap({ fileURL(path, relativeTo: $0, base: base) }).first else {
                        if !index.unresolved.contains(path) { index.unresolved.append(path) }
                        continue
                    }
                    guard visited.insert(child).inserted else { continue }
                    // Break recursive include chains and keep indexing responsive for very large projects.
                    guard file.depth < 32, index.files.count < 256,
                          let attributes = try? child.resourceValues(forKeys: [.fileSizeKey]),
                          (attributes.fileSize ?? 0) <= 4_000_000,
                          let data = try? Data(contentsOf: child),
                          let nested = try? DocumentKind.latex.read(data) else {
                        if !index.unresolved.contains(path) { index.unresolved.append(path) }
                        continue
                    }
                    let name = String(child.path.dropFirst(base.path.count + 1))
                    walk(File(id: child.path, url: child, name: name, source: nested, depth: file.depth + 1))
                }
            }
        }

        walk(File(id: rootID, url: root, name: root?.lastPathComponent ?? "Main document", source: source, depth: 0))
        return index
    }

    private static func fileURL(_ name: String, relativeTo parent: URL, base: URL) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("~"),
              !name.contains("\\"), !name.contains("\0"), !name.contains("#") else { return nil }
        let input = parent.appendingPathComponent(name)
        let file = (input.pathExtension.isEmpty ? input.appendingPathExtension("tex") : input)
            .resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(base.path + "/"),
              (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return file
    }
}

private struct LatexOutlineScanner {
    enum Item {
        case heading(String, Int, String, Int, Int)
        case include(String, relativeToParent: Bool)
    }

    private static let token = try! NSRegularExpression(pattern: #"%[^\r\n]*|\\(?:[A-Za-z@]+|[^\r\n])"#)
    private static let levels = ["part": 0, "chapter": 1, "section": 2, "subsection": 3,
                                 "subsubsection": 4, "paragraph": 5, "subparagraph": 6]
    private static let literalEnvironments: Set<String> = [
        "verbatim", "verbatim*", "Verbatim", "BVerbatim", "LVerbatim", "lstlisting", "minted", "comment", "filecontents", "filecontents*"
    ]

    private let tokens: [NSTextCheckingResult]
    private let text: NSString
    private var tokenIndex = 0
    private var position = 0
    private var line = 1

    init(_ source: String) {
        text = source as NSString
        tokens = Self.token.matches(in: source, range: NSRange(location: 0, length: text.length))
    }

    mutating func next() -> Item? {
        while tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            tokenIndex += 1
            let offset = token.range.location
            guard offset >= position else { continue }
            advance(to: NSMaxRange(token.range))
            let literal = text.substring(with: token.range)
            guard literal.hasPrefix("\\") else { continue }
            let command = String(literal.dropFirst())
            if command == "verb" {
                skipInlineLiteral()
                continue
            }
            if command == "begin", let mode = group(open: 123, close: 125), Self.literalEnvironments.contains(mode) {
                let end = text.range(of: "\\end{\(mode)}", range: NSRange(location: position, length: text.length - position))
                advance(to: end.location == NSNotFound ? text.length : NSMaxRange(end))
                continue
            }
            if command == "end", group(open: 123, close: 125) == "document" {
                position = text.length
                return nil
            }
            if let level = Self.levels[command] {
                let commandLine = line
                skipSpace()
                if character(at: position) == 42 { advance(to: position + 1) }
                let short = group(open: 91, close: 93)
                guard let full = group(open: 123, close: 125) else { continue }
                let title = (short ?? full)
                    .replacingOccurrences(of: #"(?<!\\)%[^\r\n]*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\%"#, with: "%")
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if !title.isEmpty { return .heading(command, level, title, commandLine, offset) }
            }
            if ["input", "include", "subfile", "subfileinclude"].contains(command) {
                if let path = group(open: 123, close: 125) ?? (command == "input" ? barePath() : nil) {
                    return .include(path.trimmingCharacters(in: .whitespacesAndNewlines), relativeToParent: false)
                }
            }
            if ["import", "subimport", "inputfrom", "subinputfrom", "includefrom", "subincludefrom"].contains(command),
               let folder = group(open: 123, close: 125), let file = group(open: 123, close: 125) {
                let path = folder.isEmpty ? file : (folder as NSString).appendingPathComponent(file)
                return .include(path.trimmingCharacters(in: .whitespacesAndNewlines), relativeToParent: command.hasPrefix("sub"))
            }
        }
        return nil
    }

    private func character(at offset: Int) -> UInt16? {
        offset < text.length ? text.character(at: offset) : nil
    }

    private mutating func advance(to target: Int) {
        while position < target {
            if text.character(at: position) == 10 { line += 1 }
            position += 1
        }
    }

    private mutating func skipSpace() {
        while let char = character(at: position) {
            if [9, 10, 13, 32].contains(char) {
                advance(to: position + 1)
            } else if char == 37 {
                while let next = character(at: position), next != 10 { advance(to: position + 1) }
            } else {
                break
            }
        }
    }

    private mutating func group(open: UInt16, close: UInt16) -> String? {
        skipSpace()
        guard character(at: position) == open else { return nil }
        var cursor = position + 1
        let start = cursor
        var depth = 1
        var braces = 0
        while let char = character(at: cursor) {
            if char == 92 {
                cursor = min(cursor + 2, text.length)
                continue
            }
            if char == 37 {
                while let next = character(at: cursor), next != 10 { cursor += 1 }
                continue
            }
            if open == 91 {
                if char == 123 { braces += 1 }
                if char == 125 { braces = max(0, braces - 1) }
            }
            if braces == 0, char == open { depth += 1 }
            if braces == 0, char == close { depth -= 1 }
            if depth == 0 {
                let value = text.substring(with: NSRange(location: start, length: cursor - start))
                advance(to: cursor + 1)
                return value
            }
            cursor += 1
        }
        return nil
    }

    private mutating func barePath() -> String? {
        let start = position
        while let char = character(at: position), ![9, 10, 13, 32, 37, 92, 123, 125].contains(char) {
            advance(to: position + 1)
        }
        return position == start ? nil : text.substring(with: NSRange(location: start, length: position - start))
    }

    private mutating func skipInlineLiteral() {
        if character(at: position) == 42 { advance(to: position + 1) }
        guard let delimiter = character(at: position), ![10, 13, 32].contains(delimiter) else { return }
        advance(to: position + 1)
        while let char = character(at: position), char != 10, char != 13 {
            advance(to: position + 1)
            if char == delimiter { break }
        }
    }
}
