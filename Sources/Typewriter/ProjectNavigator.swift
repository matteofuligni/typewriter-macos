import SwiftUI
import TypewriterCore

struct ProjectNavigator: View {
    let model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Project")
                    .font(.custom("Baskerville", size: 20))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    model.refreshProject()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.muted)
                .accessibilityLabel("Refresh files and outline")
                .help("Reload linked sources")
            }
            .padding(.horizontal, 13)
            .frame(height: 47)
            Rectangle().fill(Ink.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    label("File")
                    ForEach(model.project.files) { file in
                        row(file.name, icon: file.id == LatexProject.rootID ? "doc.text" : "doc",
                            indentation: file.depth, selected: model.inspectedFileID == file.id) {
                            model.reveal(fileID: file.id)
                        }
                        .help(file.url?.path ?? "Main document")
                    }
                    if !model.project.unresolved.isEmpty {
                        let count = model.project.unresolved.count
                        Text(count == 1 ? "1 file not found" : "\(count) files not found")
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.copper)
                            .padding(.horizontal, 6)
                            .help(model.project.unresolved.joined(separator: "\n"))
                    }

                    Rectangle().fill(Ink.line).frame(height: 1).padding(.vertical, 7)
                    label("Outline")
                    if model.project.headings.isEmpty {
                        Text("No chapters or sections")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.muted)
                            .padding(.horizontal, 6)
                    } else {
                        let levels = Array(Set(model.project.headings.map(\.level))).sorted()
                        ForEach(model.project.headings) { heading in
                            let depth = levels.firstIndex(of: heading.level) ?? 0
                            let symbol = heading.level <= 1 ? "book.closed" : (depth == 0 ? "text.alignleft" : "circle.fill")
                            row(heading.title, icon: symbol, indentation: depth,
                                selected: model.navigation?.fileID == heading.fileID && model.navigation?.line == heading.line) {
                                model.reveal(fileID: heading.fileID, line: heading.line)
                            }
                            .help("\(heading.title) · line \(heading.line)")
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(Ink.gutter)
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Ink.muted)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }

    private func row(_ title: String, icon: String, indentation: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: icon == "circle.fill" ? 4 : 10, weight: .medium))
                    .frame(width: 12)
                    .foregroundStyle(selected ? Ink.copper : Ink.muted)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(min(3, indentation)) * 9 + 6)
            .padding(.trailing, 6)
            .frame(height: 24)
            .background(selected ? Ink.copper.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
