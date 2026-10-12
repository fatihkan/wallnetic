#!/bin/bash
set -euo pipefail

probe_sources=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
probe_repo=$(git -C "$probe_sources" rev-parse --show-toplevel)
mkdir -p "$probe_repo/.build"
probe_output=$(mktemp -d "$probe_repo/.build/screensaver-probe.XXXXXX")
probe_bundle="$probe_output/WallneticScreenSaverProbe.saver"
probe_sdk=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p "$probe_bundle/Contents/MacOS" "$probe_bundle/Contents/Resources"
cp "$probe_sources/Info.plist" "$probe_bundle/Contents/Info.plist"
cp "$probe_repo/src/Wallnetic/Resources/Samples/AuroraSample.mp4" "$probe_bundle/Contents/Resources/"
cp "$probe_repo/LICENSE" "$probe_bundle/Contents/Resources/"

xcrun clang -isysroot "$probe_sdk" -mmacosx-version-min=13.0 \
    -arch arm64 -arch x86_64 -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -bundle -framework AppKit -framework ScreenSaver -framework AVFoundation -framework QuartzCore -framework CoreMedia \
    "$probe_sources/ScreenSaverView.m" -o "$probe_bundle/Contents/MacOS/WallneticScreenSaverProbe"

# A local ad-hoc signature only. No signing account, entitlements, production
# certificates, notarization request, Gatekeeper change, or installation.
codesign --force --sign - --timestamp=none "$probe_bundle"
xcrun clang -isysroot "$probe_sdk" -mmacosx-version-min=13.0 \
    -arch arm64 -arch x86_64 -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework AppKit -framework ScreenSaver -framework CoreMedia \
    "$probe_sources/Host.m" -o "$probe_output/ScreenSaverProbeHost"
codesign --force --sign - --timestamp=none "$probe_output/ScreenSaverProbeHost"
codesign --verify --strict "$probe_bundle"
lipo -archs "$probe_bundle/Contents/MacOS/WallneticScreenSaverProbe"
printf 'Built research artifacts: %s\n' "$probe_output"
if [[ "${1:-}" == "--run" ]]; then
    "$probe_output/ScreenSaverProbeHost" "$probe_bundle"
fi
