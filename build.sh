#!/bin/bash
# Build Paperlayer.app into build/. Pass "install" to also copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Paperlayer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macosx13.0 -o "$APP/Contents/MacOS/Paperlayer" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/Paperlayer.app
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/Paperlayer.app"
fi
