#!/bin/zsh
# Compila e empacota VolumeTweak.app. Uso: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/VolumeTweak.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/VolumeTweak "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "OK: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x VolumeTweak 2>/dev/null || true
  rm -rf /Applications/VolumeTweak.app
  cp -R "$APP" /Applications/
  open /Applications/VolumeTweak.app
  echo "Instalado em /Applications e iniciado."
fi
