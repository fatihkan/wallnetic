#!/bin/bash
set -euo pipefail

saver_tools=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ $# != 4 || "$1" != "--identity" || "$3" != "--notary-profile" || -z "$2" || -z "$4" || "$2" == "-" ]]; then
    echo "Usage: tools/screensaver/package.sh --identity 'Developer ID Application: …' --notary-profile KEYCHAIN_PROFILE" >&2
    echo "Requires configured signing credentials; submits a fresh candidate to Apple. Does not publish or install." >&2
    exit 2
fi
saver_identity="$2"
saver_profile="$4"
saver_output=$("$saver_tools/build.sh")
saver_bundle="$saver_output/WallneticScreenSaver.saver"
codesign --force --sign "$saver_identity" --options runtime --timestamp "$saver_bundle"
python3 "$saver_tools/validate.py" --distribution "$saver_bundle"

# Use a DMG, whose notarization ticket can be stapled. No custom installer,
# privileged helper, automatic installation or quarantine/security modification.
mkdir "$saver_output/payload"
ditto "$saver_bundle" "$saver_output/payload/WallneticScreenSaver.saver"
cp "$saver_tools/INSTALL.txt" "$saver_output/payload/INSTALL.txt"
saver_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$saver_bundle/Contents/Info.plist")
saver_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$saver_bundle/Contents/Info.plist")
saver_dmg="$saver_output/WallneticScreenSaver-$saver_version-$saver_build-candidate.dmg"
hdiutil create -volname 'Wallnetic Screen Saver Candidate' -srcfolder "$saver_output/payload" \
    -format UDZO "$saver_dmg"
codesign --sign "$saver_identity" --timestamp "$saver_dmg"
xcrun notarytool submit "$saver_dmg" --keychain-profile "$saver_profile" --wait \
    --output-format json > "$saver_output/notarization.json"
python3 - "$saver_output/notarization.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file:
    result = json.load(file)
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Review the submission log; do not distribute.')
PY
xcrun stapler staple "$saver_dmg"
xcrun stapler validate "$saver_dmg"
codesign --verify --strict "$saver_dmg"
hdiutil verify "$saver_dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$saver_dmg"
shasum -a 256 "$saver_dmg" > "$saver_output/SHA256SUMS.txt"
printf 'Notarized candidate: %s\nPhysical host and fresh-download installation gates still apply.\n' "$saver_dmg"
