#!/bin/bash

set -e

# URL="https://github.com/JanisErdmanis/Jumbo/releases/download/v26.08.08/jumbo-26.8.8-aarch64.dmg"
# DMG="/tmp/jumbo-26.8.8-aarch64.dmg"

# echo "Downloading Jumbo..."
# curl -L --progress-bar -o "$DMG" "$URL"
DMG="$1"

echo
echo "Mounting DMG..."

MOUNT_POINT=$(hdiutil attach "$DMG" -nobrowse | awk -F '\t' '/\/Volumes\// {print $NF; exit}')

if [ -z "$MOUNT_POINT" ]; then
    echo "Error: failed to mount DMG."
    exit 1
fi

echo "Mounted at: $MOUNT_POINT"

# Make sure the DMG is detached if the script exits unexpectedly
cleanup() {
    if [ -n "$MOUNT_POINT" ] && mount | grep -Fq "$MOUNT_POINT"; then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi

    rm -f "$DMG"
}

trap cleanup EXIT

echo "Searching for application..."

APP=$(find "$MOUNT_POINT" -maxdepth 2 -type d -name "*.app" -print -quit)

if [ -z "$APP" ]; then
    echo "Error: no .app application found in the DMG."
    exit 1
fi

APP_NAME=$(basename "$APP")

echo "Found: $APP_NAME"
echo "Installing to /Applications..."

sudo rm -rf "/Applications/$APP_NAME"
sudo cp -R "$APP" "/Applications/$APP_NAME"

echo "Removing quarantine attribute..."

sudo xattr -dr com.apple.quarantine "/Applications/$APP_NAME"
#sudo xattr -d com.apple.quarantine "/Applications/$APP_NAME"

echo
echo "Installation complete:"
echo "  /Applications/$APP_NAME"
