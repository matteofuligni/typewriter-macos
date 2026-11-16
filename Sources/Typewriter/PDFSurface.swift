import AppKit
import Observation
import PDFKit
import SwiftUI

@MainActor @Observable final class PreviewControls {
    var page = 0
    var total = 0
    var fitted = true
    var aspect: CGFloat = 595.28 / 841.89
    @ObservationIgnored weak var view: PDFView?

    func fit() {
        fitted = true
        view?.autoScales = true
    }

    func zoom(_ direction: Int) {
        guard let view else { return }
        fitted = false
        view.autoScales = false
        if direction > 0 { view.zoomIn(nil) } else { view.zoomOut(nil) }
    }

    func go(_ delta: Int) {
        guard let view else { return }
        if delta > 0 { view.goToNextPage(nil) } else { view.goToPreviousPage(nil) }
        synchronize()
    }

    func synchronize() {
        guard let view, let document = view.document else { return }
        let index = view.currentPage.map { document.index(for: $0) }
        total = document.pageCount
        page = index.flatMap { $0 < document.pageCount ? $0 + 1 : nil } ?? (total > 0 ? 1 : 0)
        if let box = view.currentPage?.bounds(for: .cropBox), box.width > 0, box.height > 0 {
            aspect = box.width / box.height
        }
    }
}

struct PDFSurface: NSViewRepresentable {
    let data: Data
    let revision: Int
    let controls: PreviewControls

    func makeCoordinator() -> Coordinator {
        Coordinator(controls: controls)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = Ink.nsPreview
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.pageShadowsEnabled = false
        view.interpolationQuality = .high
        view.autoScales = true
        view.maxScaleFactor = 5.0
        view.minScaleFactor = 0.16
        view.setAccessibilityLabel("PDF Preview")
        controls.view = view
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.pageChanged), name: .PDFViewPageChanged, object: view
        )
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard revision != context.coordinator.revision, let document = PDFDocument(data: data) else { return }
        context.coordinator.revision = revision
        let oldPage = max(0, controls.page - 1)
        let scale = view.scaleFactor
        let fit = view.document == nil || view.autoScales
        view.document = document
        if let page = document.page(at: min(oldPage, document.pageCount - 1)) {
            view.go(to: page)
        }
        if fit {
            view.autoScales = true
        } else {
            view.autoScales = false
            view.scaleFactor = scale
        }
        DispatchQueue.main.async { controls.synchronize() }
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator, name: .PDFViewPageChanged, object: nsView)
    }

    @MainActor final class Coordinator: NSObject {
        weak var controls: PreviewControls?
        var revision = -1

        init(controls: PreviewControls) { self.controls = controls }

        @objc func pageChanged() {
            // PDFKit posts during document replacement, which can coincide with a SwiftUI update.
            DispatchQueue.main.async { [weak self] in self?.controls?.synchronize() }
        }
    }
}
