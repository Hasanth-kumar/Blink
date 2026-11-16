#!/bin/bash
#
# Builds Blink.app without Xcode. Needs only the Command Line Tools
# (install them once with:  xcode-select --install).
#
#   bash build.sh            build  ->  build/Blink.app
#   bash build.sh run        build, then launch it
#   bash build.sh install    build, copy to /Applications, then launch it
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Blink"
ACTION="${1:-build}"
APP="build/${APP_NAME}.app"

if ! command -v swift >/dev/null 2>&1; then
    echo "error: 'swift' was not found. Install the Command Line Tools with: xcode-select --install" >&2
    exit 1
fi

echo "==> Compiling (this takes a minute the first time)"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling ${APP}"
BINARY="${BIN_DIR}/${APP_NAME}"
if [ ! -f "${BINARY}" ]; then
    # Newer toolchains may place products elsewhere under .build; look for it.
    BINARY="$(find .build -type f -name "${APP_NAME}" -perm -u+x -not -path "*.dSYM/*" 2>/dev/null | head -n 1)"
fi
if [ -z "${BINARY}" ] || [ ! -f "${BINARY}" ]; then
    echo "error: the build succeeded but the ${APP_NAME} executable could not be found under .build" >&2
    exit 1
fi

# Assemble and sign in a temporary folder. A Desktop or Documents folder that syncs with
# iCloud keeps adding file attributes, and code signing refuses to sign files that have them.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/blink-build.XXXXXX")"
STAGED_APP="${STAGE}/${APP_NAME}.app"
mkdir -p "${STAGED_APP}/Contents/MacOS" "${STAGED_APP}/Contents/Resources"
cp "${BINARY}" "${STAGED_APP}/Contents/MacOS/${APP_NAME}"
cp "Blink/Info.plist" "${STAGED_APP}/Contents/Info.plist"
cp "Blink/Resources/AppIcon.icns" "${STAGED_APP}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${STAGED_APP}/Contents/PkgInfo"
xattr -cr "${STAGED_APP}" 2>/dev/null || true

echo "==> Signing for this Mac"
codesign --force --sign - --entitlements "Blink/Blink.entitlements" "${STAGED_APP}"

mkdir -p build
# Remove only this script's own previous output, then move the finished app into place.
rm -rf "${APP}"
ditto "${STAGED_APP}" "${APP}"
rm -rf "${STAGE}"

echo "==> Built ${APP}"

BUNDLE_ID="local.blink.app"

# Stops a running copy of this app only (matched by its full path, never by name alone).
stop_running() {
    pkill -f "$1/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
}

# Prints the bundle identifier of an app, or nothing if it cannot be read.
bundle_id_of() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

# Install for every user when that is allowed; otherwise use this user's own Applications folder.
INSTALL_DIR="/Applications"
if [ ! -w "${INSTALL_DIR}" ]; then
    INSTALL_DIR="${HOME}/Applications"
    mkdir -p "${INSTALL_DIR}"
fi
DEST="${INSTALL_DIR}/${APP_NAME}.app"

case "${ACTION}" in
    run)
        stop_running "$(pwd)/${APP}"
        if [ -d "${DEST}" ] && [ "$(bundle_id_of "${DEST}")" = "${BUNDLE_ID}" ]; then
            stop_running "${DEST}"
        fi
        open "${APP}"
        ;;
    install)
        if [ -d "${DEST}" ]; then
            EXISTING_ID="$(bundle_id_of "${DEST}")"
            if [ "${EXISTING_ID}" != "${BUNDLE_ID}" ]; then
                echo "error: ${DEST} already exists and is a different app (${EXISTING_ID:-unknown}). Not replacing it." >&2
                echo "       Rename this app first (see README, 'Renaming the app')." >&2
                exit 1
            fi
            stop_running "${DEST}"
            # Move the old copy to the Trash rather than deleting it.
            mv "${DEST}" "${HOME}/.Trash/${APP_NAME}-$(date +%Y%m%d-%H%M%S).app"
        fi
        stop_running "$(pwd)/${APP}"
        ditto "${APP}" "${DEST}"
        open "${DEST}"
        echo "==> Installed to ${DEST}"
        ;;
    build)
        echo "    Launch it with:  open ${APP}"
        ;;
    *)
        echo "Unknown option '${ACTION}'. Use: build, run or install." >&2
        exit 1
        ;;
esac
