import AppKit
import TypewriterCore

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var current: TypewriterDocument? { NSDocumentController.shared.currentDocument as? TypewriterDocument }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SoundBank.shared.prepare()
        TeXManager.shared.checkEnvironment()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        make(.latex)
        return true
    }

    @objc func newLatex(_ sender: Any?) { make(.latex) }
    @objc func newWord(_ sender: Any?) { make(.word) }
    @objc func newText(_ sender: Any?) { make(.text) }
    @objc func openDocument(_ sender: Any?) { NSDocumentController.shared.openDocument(sender) }
    @objc func compile(_ sender: Any?) { current?.workspace.compileNow() }
    @objc func exportPDF(_ sender: Any?) { current?.exportPDF() }
    @objc func toggleSound(_ sender: Any?) { SoundBank.shared.enabled.toggle() }
    @objc func toggleAutomatic(_ sender: Any?) { current?.workspace.automatic.toggle() }
    @objc func showDependencies(_ sender: Any?) { current?.workspace.showsDependencies = true }
    @objc func toggleNavigator(_ sender: Any?) { current?.workspace.showsNavigator.toggle() }
    @objc func toggleTypewriterMode(_ sender: Any?) { current?.workspace.toggleTypewriterMode() }

    private func make(_ kind: DocumentKind) {
        let controller = NSDocumentController.shared
        let doc = TypewriterDocument()
        doc.fileType = kind.rawValue
        doc.initialize(kind: kind)
        controller.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(compile(_:)):
            return current?.workspace.kind == .latex && TeXManager.shared.isAvailable && !TeXManager.shared.isInstalling
        case #selector(exportPDF(_:)):
            if let status = current?.workspace.status, case .ready = status { return true }
            return false
        case #selector(toggleSound(_:)):
            item.state = SoundBank.shared.enabled ? .on : .off
            return current != nil
        case #selector(showDependencies(_:)):
            return current?.workspace.kind == .latex
        case #selector(toggleNavigator(_:)):
            item.state = current?.workspace.showsNavigator == true ? .on : .off
            return current?.workspace.kind == .latex
        case #selector(toggleTypewriterMode(_:)):
            item.state = current?.workspace.typewriterMode == true ? .on : .off
            return current != nil
        case #selector(toggleAutomatic(_:)):
            item.state = current?.workspace.automatic == true ? .on : .off
            return current?.workspace.kind == .latex
        default:
            return true
        }
    }

    func installMenus() {
        let bar = NSMenu()
        func section(_ name: String) -> NSMenu {
            let item = NSMenuItem()
            let menu = NSMenu(title: name)
            item.submenu = menu
            bar.addItem(item)
            return menu
        }
        func add(_ title: String, _ action: Selector, _ key: String = "", to menu: NSMenu,
                 target: AnyObject? = nil, shift: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : .command
            menu.addItem(item)
        }

        let app = section("Typewriter")
        add("About Typewriter", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: app)
        app.addItem(.separator())
        add("Hide Typewriter", #selector(NSApplication.hide(_:)), "h", to: app)
        add("Quit Typewriter", #selector(NSApplication.terminate(_:)), "q", to: app)

        let file = section("File")
        add("New LaTeX Document", #selector(newLatex(_:)), "n", to: file, target: self)
        add("New Word Document", #selector(newWord(_:)), "n", to: file, target: self, shift: true)
        add("New Plain Text Document", #selector(newText(_:)), to: file, target: self)
        file.addItem(.separator())
        add("Open…", #selector(openDocument(_:)), "o", to: file, target: self)
        file.addItem(.separator())
        add("Close", #selector(NSWindow.performClose(_:)), "w", to: file)
        add("Save…", #selector(NSDocument.save(_:)), "s", to: file)
        add("Save As…", #selector(NSDocument.saveAs(_:)), "s", to: file, shift: true)
        add("Export PDF…", #selector(exportPDF(_:)), "e", to: file, target: self, shift: true)

        let edit = section("Edit")
        add("Undo", Selector(("undo:")), "z", to: edit)
        add("Redo", Selector(("redo:")), "z", to: edit, shift: true)
        edit.addItem(.separator())
        add("Cut", #selector(NSText.cut(_:)), "x", to: edit)
        add("Copy", #selector(NSText.copy(_:)), "c", to: edit)
        add("Paste", #selector(NSText.paste(_:)), "v", to: edit)
        add("Select All", #selector(NSText.selectAll(_:)), "a", to: edit)
        let find = NSMenuItem(title: "Find…", action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        edit.addItem(find)

        let view = section("View")
        add("Typewriter Mode", #selector(toggleTypewriterMode(_:)), "t", to: view, target: self, shift: true)
        add("LaTeX Navigator", #selector(toggleNavigator(_:)), "l", to: view, target: self, shift: true)
        add("LaTeX Dependencies…", #selector(showDependencies(_:)), to: view, target: self)
        add("Compile LaTeX", #selector(compile(_:)), "r", to: view, target: self)
        add("Auto-Compile", #selector(toggleAutomatic(_:)), to: view, target: self)
        add("Keystroke Sounds", #selector(toggleSound(_:)), to: view, target: self)
        view.addItem(.separator())
        add("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", to: view, shift: true)

        let window = section("Window")
        add("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", to: window)
        add("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), to: window)
        NSApp.windowsMenu = window
        NSApp.mainMenu = bar
    }
}

let application = NSApplication.shared
let delegate = ApplicationDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
delegate.installMenus()
application.run()
