#!/bin/bash
set -euo pipefail

probe_sources=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ $# -gt 1 || ( $# == 1 && "$1" != "--run" && "$1" != "--benchmark" ) ]]; then
    echo "Usage: tools/screensaver-probe/build.sh [--run|--benchmark]" >&2
    exit 2
fi
probe_output=$("$probe_sources/../screensaver/build.sh")
probe_sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -isysroot "$probe_sdk" -mmacosx-version-min=13.0 \
    -arch arm64 -arch x86_64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework AppKit -framework ScreenSaver -framework CoreMedia -framework AVFoundation \
    "$probe_sources/Host.m" -o "$probe_output/ScreenSaverProbeHost"
codesign --force --sign - --timestamp=none "$probe_output/ScreenSaverProbeHost"
codesign --verify --strict "$probe_output/ScreenSaverProbeHost"
printf 'Built candidate and test host: %s\n' "$probe_output"
if [[ $# == 1 ]]; then
    python3 "$probe_sources/run.py" "$probe_output" "$1"
fi
