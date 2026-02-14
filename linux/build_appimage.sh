#!/bin/bash
# Build a Linux AppImage for SwiftDrop.
#
# Prerequisites:
#   - Flutter SDK on PATH
#   - appimagetool (https://appimage.github.io/appimagetool/)
#   - Linux build deps: ninja-build, libgtk-3-dev
#
# Usage: ./build_appimage.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/linux/x64/release/bundle"
APPDIR="$PROJECT_ROOT/build/SwiftDrop.AppDir"

echo "==> Building Flutter Linux release..."
cd "$PROJECT_ROOT"
flutter build linux --release

echo "==> Creating AppDir structure..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy the release bundle.
cp -r "$BUILD_DIR"/* "$APPDIR/usr/bin/"
# Move libs to standard location.
if [ -d "$APPDIR/usr/bin/lib" ]; then
  cp -r "$APPDIR/usr/bin/lib"/* "$APPDIR/usr/lib/"
  rm -rf "$APPDIR/usr/bin/lib"
fi

# Copy desktop entry.
cp "$SCRIPT_DIR/swiftdrop.desktop" "$APPDIR/usr/share/applications/"
cp "$SCRIPT_DIR/swiftdrop.desktop" "$APPDIR/"

# Create AppRun.
cat > "$APPDIR/AppRun" << 'APPRUN'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/swiftdrop" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

echo "==> Packaging AppImage..."
if command -v appimagetool &> /dev/null; then
  appimagetool "$APPDIR" "$PROJECT_ROOT/build/SwiftDrop-x86_64.AppImage"
  echo "==> AppImage created: build/SwiftDrop-x86_64.AppImage"
else
  echo "==> appimagetool not found. AppDir ready at: build/SwiftDrop.AppDir/"
  echo "    Install appimagetool to create the final .AppImage file."
fi
