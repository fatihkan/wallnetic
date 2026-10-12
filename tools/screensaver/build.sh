#!/bin/bash
set -euo pipefail

saver_tools=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
saver_repo=$(git -C "$saver_tools" rev-parse --show-toplevel)
saver_sources="$saver_repo/src/WallneticScreenSaver"
if [[ $# != 0 ]]; then
    echo "Usage: tools/screensaver/build.sh (prints a new local build directory)" >&2
    exit 2
fi
mkdir -p "$saver_repo/.build"
saver_output=$(mktemp -d "$saver_repo/.build/screensaver-candidate.XXXXXX")
saver_bundle="$saver_output/WallneticScreenSaver.saver"
saver_sdk=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p "$saver_bundle/Contents/MacOS" "$saver_bundle/Contents/Resources"
cp "$saver_sources/Info.plist" "$saver_bundle/Contents/Info.plist"
cp "$saver_repo/LICENSE" "$saver_bundle/Contents/Resources/LICENSE.txt"
sed 's|../../LICENSE|LICENSE.txt|' "$saver_repo/catalog/media/README.md" > "$saver_bundle/Contents/Resources/MEDIA-LICENSE.md"
cp "$saver_repo/catalog/media/lagoon.mp4" "$saver_repo/catalog/media/ember.mp4" "$saver_bundle/Contents/Resources/"

# Pin the small, known original assets; never fetch media or silently package a
# replacement file. Deliberate asset updates require an updated build manifest.
python3 "$saver_tools/validate.py" --resources-only "$saver_bundle" >&2
xcrun clang -isysroot "$saver_sdk" -mmacosx-version-min=13.0 \
    -arch arm64 -arch x86_64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
    -bundle -framework AppKit -framework ScreenSaver -framework AVFoundation -framework QuartzCore -framework CoreMedia \
    "$saver_sources/WallneticScreenSaverView.m" -o "$saver_bundle/Contents/MacOS/WallneticScreenSaver"

# Local artifacts only. The separate packaging command requires an explicit
# Developer ID identity; neither command installs or selects a screen saver.
codesign --force --sign - --timestamp=none "$saver_bundle"
python3 "$saver_tools/validate.py" "$saver_bundle" >&2
printf '%s\n' "$saver_output"
