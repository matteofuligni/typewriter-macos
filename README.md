# Typewriter

Typewriter is a native writing app for Apple Silicon Macs running macOS 14 or later. It uses AppKit and SwiftUI for the editor and PDFKit for the preview.

## Writing

Open `dist/Typewriter.app`. The first window opens an English LaTeX template. Use **New** to start a LaTeX, Word, or plain-text document. Drag the divider to resize the editor and PDF preview.

- **⇧⌘T** opens **Typewriter Mode**. The current line stays near the bottom of the sheet as the text above it moves up. Press **Esc** or click **Exit Typewriter Mode** to return to the workspace.
- **⌘N** creates a LaTeX document. **⇧⌘N** creates a Word document. **⌘O** opens a file and **⌘S** saves it.
- **⇧⌘L** toggles the LaTeX navigator. **File** lists the main document and linked files. **Outline** jumps to chapters and sections. **Edit** opens a linked file in a separate window.
- **⌘R** compiles LaTeX. **Auto** compiles after a pause in typing. The last valid PDF stays visible after a compilation error. **⇧⌘E** exports the current PDF.
- **Keystroke Sounds** offers Classic, Crisp, and Soft sounds and a mute switch.

Word documents are edited as plain text and receive a new layout when saved as DOCX. Use **Save As…** to preserve the original document with its styles, tables, and images.

## LaTeX setup

Typewriter checks the local LaTeX installation at each launch by compiling its template. If that check fails, the first LaTeX workspace opens **LaTeX Dependencies**. When a LaTeX document compiles, pdfLaTeX checks the packages that document uses. The panel can look up package files reported missing and install packages by name.

Choose **Dependencies → Install TeX Live** to download the official installer and packages from CTAN. Installation runs under your user account and the installed packages work offline. Typewriter also detects an existing MacTeX installation. Network requests occur when you install, update, or search for packages.

TeX Live is an external dependency for LaTeX preview and export. Typewriter runs pdfLaTeX as a separate process. The source repository and default app bundle contain Typewriter's own code and assets. TeX Live serves its installer and packages directly from CTAN under their respective licenses. [TeX Live copying conditions](https://github.com/TeX-Live/installer/blob/master/LICENSE.TL)

The PDF preview runs pdfLaTeX. It resolves relative files next to the saved main document. It does not use shell escape or run external bibliography tools.

## Build

Build on Apple Silicon with Xcode 16 or later. The default bundle contains the app and its assets. TeX Live can be installed from the app.

```sh
./scripts/build-app.sh
open dist/Typewriter.app
```

For local development with a bundled engine, run `TYPEWRITER_BUNDLE_TEX=1 ./scripts/build-app.sh` with Python 3 and MacTeX available. Set `TYPEWRITER_TEXBIN` if TeX Live is installed in a different location. The build script uses an ad hoc signature for local testing. See the [distribution review](Packaging/DISTRIBUTION.md) for public release requirements.

Open `Package.swift` in Xcode for development. Run `swift test` for the local tests. Set `TYPEWRITER_TEST_TEX` to an embedded engine root for offline compiler integration tests. Set `TYPEWRITER_TEST_NETWORK_INSTALL=1` to test the official CTAN download and install in a temporary directory.

In a workspace sandbox that prevents nested sandboxing, set `TYPEWRITER_SWIFTPM_NO_SANDBOX=1` for the build script and use `swift test --disable-sandbox` for tests.

## License

Typewriter's code and original assets are available under the [MIT License](LICENSE). TeX Live and its packages retain their own licenses.
