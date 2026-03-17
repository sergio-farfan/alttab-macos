#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AltTab"
SCHEME="AltTab"
CONFIG="Release"
PROJECT_DIR="$(cd "$(dirname "$0")/AltTab" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_PATH="${BUILD_DIR}/Build/Products/${CONFIG}/${APP_NAME}.app"

# Default install to ~/Applications (no sudo needed); use --system for /Applications
INSTALL_DIR="${HOME}/Applications"

usage() {
    cat <<EOF
Usage: $(basename "$0") [command] [options]

Commands:
  build       Build the app (Release configuration)
  install     Build and install to ~/Applications (user-level)
  run         Build and launch immediately
  clean       Remove build artifacts
  uninstall   Remove installed app and kill running instance

Options:
  --system    Install to /Applications instead of ~/Applications (may need sudo)

Examples:
  ./build.sh build                  # Build only
  ./build.sh install                # Build and install to ~/Applications
  sudo ./build.sh install --system  # Build and install to /Applications
  ./build.sh run                    # Build and launch from build dir
  ./build.sh uninstall              # Remove from ~/Applications
  sudo ./build.sh uninstall --system  # Remove from /Applications

Default: build
EOF
}

# Parse --system flag from any position
for arg in "$@"; do
    if [[ "$arg" == "--system" ]]; then
        INSTALL_DIR="/Applications"
    fi
done

check_xcode() {
    if ! command -v xcodebuild &>/dev/null; then
        echo "Error: xcodebuild not found. Install Xcode from the App Store."
        exit 1
    fi
    # Verify full Xcode, not just Command Line Tools
    local dev_dir
    dev_dir="$(xcode-select -p 2>/dev/null)"
    if [[ "$dev_dir" == */CommandLineTools ]]; then
        echo "Error: Full Xcode required (not just Command Line Tools)."
        echo "  Install Xcode from App Store, then run:"
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi
}

do_build() {
    check_xcode
    echo "Building ${APP_NAME} (${CONFIG})..."
    cd "$PROJECT_DIR"
    xcodebuild \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -derivedDataPath "$BUILD_DIR" \
        build 2>&1 | tail -5

    echo ""
    echo "Build succeeded: ${APP_PATH}"
}

do_install() {
    do_build

    # Kill running instance
    pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    sleep 0.5

    # Create install dir if needed (for ~/Applications)
    mkdir -p "${INSTALL_DIR}"

    echo "Installing to ${INSTALL_DIR}/${APP_NAME}.app ..."
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    cp -R "$APP_PATH" "${INSTALL_DIR}/"

    echo ""
    echo "Installed successfully!"
    echo ""
    echo "Launch:"
    echo "  open ${INSTALL_DIR}/${APP_NAME}.app"
    echo ""
    echo "First launch checklist:"
    echo "  1. Grant Accessibility:  System Settings → Privacy & Security → Accessibility → AltTab ON"
    echo "  2. Grant Screen Recording (optional, for live thumbnails):"
    echo "     System Settings → Privacy & Security → Screen Recording → AltTab ON"
}

do_run() {
    do_build
    pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    sleep 0.5
    echo "Launching ${APP_NAME}..."
    open "$APP_PATH"
}

do_clean() {
    echo "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    echo "Done."
}

do_uninstall() {
    echo "Uninstalling ${APP_NAME} from ${INSTALL_DIR}..."
    pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    echo "Removed ${APP_NAME} from ${INSTALL_DIR}."
    echo "Note: You may want to remove it from Login Items in System Settings."
}

# Get first non-flag argument as the command
CMD="build"
for arg in "$@"; do
    if [[ "$arg" != --* ]]; then
        CMD="$arg"
        break
    fi
done

case "$CMD" in
    build)     do_build ;;
    install)   do_install ;;
    run)       do_run ;;
    clean)     do_clean ;;
    uninstall) do_uninstall ;;
    -h|--help|help) usage ;;
    *)
        echo "Unknown command: $CMD"
        usage
        exit 1
        ;;
esac
