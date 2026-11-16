#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
TEXBIN="${TYPEWRITER_TEXBIN:-/Library/TeX/texbin}"
BUNDLE_TEX="${TYPEWRITER_BUNDLE_TEX:-0}"
if [[ "$BUNDLE_TEX" == 1 && ! -x "$TEXBIN/pdftex" ]]; then
  print -u2 "A local TeX Live installation is required to build the bundled engine."
  print -u2 "Install MacTeX or set TYPEWRITER_TEXBIN to its executable directory."
  exit 1
fi
SCRATCH="$PWD/.build/typewriter-release"
TEMP_BUILD=""
STAGE=""
cleanup() {
  if [[ -n "$TEMP_BUILD" ]]; then rm -rf "$TEMP_BUILD"; fi
  if [[ -n "$STAGE" ]]; then rm -rf "$STAGE"; fi
}
trap cleanup EXIT
SWIFT_FLAGS=(--manifest-cache local)
if [[ "${TYPEWRITER_SWIFTPM_NO_SANDBOX:-0}" == 1 ]]; then
  TEMP_BUILD="$(mktemp -d /private/tmp/typewriter-build.XXXXXX)"
  SCRATCH="$TEMP_BUILD/build"
  SWIFT_FLAGS+=(--disable-sandbox -debug-info-format none)
fi
SWIFT_FLAGS+=(--scratch-path "$SCRATCH")
export CLANG_MODULE_CACHE_PATH="$SCRATCH/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build "${SWIFT_FLAGS[@]}" -c release --arch arm64
BIN="$(swift build "${SWIFT_FLAGS[@]}" -c release --arch arm64 --show-bin-path)"
STAGE="$(mktemp -d "$PWD/.build/bundle.XXXXXX")"
APP="$STAGE/Typewriter.app"
mkdir -p "$APP/Contents/"{MacOS,Resources}
cp Packaging/Info.plist "$APP/Contents/"
cp Packaging/Typewriter.icns "$APP/Contents/Resources/"
cp "$BIN/Typewriter" "$APP/Contents/MacOS/"
cp -R "$BIN/Typewriter_Typewriter.bundle" "$APP/Contents/Resources/"
if [[ "$BUNDLE_TEX" == 1 ]]; then
  python3 scripts/bundle-tex.py --texbin "$TEXBIN" "$APP/Contents/Resources/TeX"
fi
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
if [[ -e dist/Typewriter.app ]]; then
  PREVIOUS="$STAGE/previous.app"
  mv dist/Typewriter.app "$PREVIOUS"
  if ! mv "$APP" dist/; then
    mv "$PREVIOUS" dist/Typewriter.app
    exit 1
  fi
else
  mv "$APP" dist/
fi
print -r -- "$PWD/dist/Typewriter.app"
