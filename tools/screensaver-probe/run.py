#!/usr/bin/env python3
"""Exercise only locally built candidates in ordinary windows, never the system host."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
mode = parser.add_mutually_exclusive_group(required=True)
mode.add_argument("--run", action="store_true")
mode.add_argument("--benchmark", action="store_true")
args = parser.parse_args()
root = args.output.resolve(strict=True)
bundle = root / "WallneticScreenSaver.saver"
host = root / "ScreenSaverProbeHost"
validator = Path(__file__).resolve().parents[1] / "screensaver/validate.py"


def run(*command, succeeds=True):
    result = subprocess.run(command, timeout=120, check=False)
    if (result.returncode == 0) != succeeds:
        raise SystemExit(f"Unexpected exit {result.returncode}: {command[0]}")


run(sys.executable, str(validator), str(bundle))
run(sys.executable, str(validator), "--distribution", str(bundle), succeeds=False)
print("PASS: ad-hoc candidate rejected for distribution", flush=True)
run(str(host), str(bundle), *(["--benchmark"] if args.benchmark else []))

# Every fixture is a new private copy of our candidate, with a fresh ad-hoc
# signature. No media outside this build directory is changed or executed.
for scenario in ["missing", "empty", "corrupt", "oversized", "symlink"]:
    with tempfile.TemporaryDirectory(prefix="fixture-" + scenario + "-", dir=root) as temporary:
        fixture = Path(temporary) / "WallneticScreenSaver.saver"
        shutil.copytree(bundle, fixture)
        for name in ["lagoon.mp4", "ember.mp4"]:
            media = fixture / "Contents/Resources" / name
            media.unlink()
            if scenario == "empty":
                media.touch()
            elif scenario == "corrupt":
                media.write_bytes(b"invalid video data")
            elif scenario == "oversized":
                with media.open("wb") as file:
                    file.truncate(2 * 1024 * 1024 + 1)
            elif scenario == "symlink":
                media.symlink_to(bundle / "Contents/Resources" / name)
        run(sys.executable, str(validator), str(fixture), succeeds=False)
        # codesign may reject symlink contents that escape the bundle; use an
        # internal link here, which remains rejected by runtime and packaging.
        if scenario == "symlink":
            for name in ["lagoon", "ember"]:
                media = fixture / "Contents/Resources" / (name + ".mp4")
                media.unlink()
                shutil.copyfile(bundle / "Contents/Resources" / (name + ".mp4"), media.with_suffix(".data"))
                media.symlink_to(name + ".data")
        run("codesign", "--force", "--sign", "-", "--timestamp=none", str(fixture))
        print("SCENARIO: " + scenario, flush=True)
        run(str(host), str(fixture), "--expect-fallback")

for scenario in ["identifier", "extra-code", "license"]:
    with tempfile.TemporaryDirectory(prefix="package-" + scenario + "-", dir=root) as temporary:
        fixture = Path(temporary) / "WallneticScreenSaver.saver"
        shutil.copytree(bundle, fixture)
        if scenario == "identifier":
            path = fixture / "Contents/Info.plist"
            info = plistlib.loads(path.read_bytes())
            info["CFBundleIdentifier"] = "com.example.unexpected"
            path.write_bytes(plistlib.dumps(info))
        elif scenario == "extra-code":
            (fixture / "Contents/MacOS/UnexpectedHelper").write_bytes(b"unexpected payload")
        else:
            (fixture / "Contents/Resources/LICENSE.txt").unlink()
        run(sys.executable, str(validator), str(fixture), succeeds=False)
        print("PASS: packaging rejected " + scenario, flush=True)
print("RESULT: all candidate scenarios and 9 packaging rejection checks passed", flush=True)
