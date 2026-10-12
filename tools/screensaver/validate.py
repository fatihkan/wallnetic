#!/usr/bin/env python3
"""Validate our standalone candidate, never modify or execute its code."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess

ASSETS = {
    "lagoon.mp4": (356097, "aaa7f3abceb4c8289ea65fb4bf844d935b9ae593042a1ea23e43f5c0b89cdd7f"),
    "ember.mp4": (334501, "ec2eb9a193eeac4caefd3d0af0e28d06a0effeb075e7770671e3c75eb2155bc9"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True)


def validate(bundle, resources_only=False, distribution=False):
    require(bundle.is_dir() and not bundle.is_symlink(), "Expected a real .saver directory")
    require(not any(path.is_symlink() for path in bundle.rglob("*")), "Bundle contains a symbolic link")
    resources = bundle / "Contents/Resources"
    require({path.name for path in resources.iterdir()} == set(ASSETS) | {"LICENSE.txt", "MEDIA-LICENSE.md"},
            "Unexpected or missing resource; no external media/code may be packaged")
    for name, (size, digest) in ASSETS.items():
        path = resources / name
        require(path.is_file() and path.stat().st_size == size, f"Unexpected size: {name}")
        require(hashlib.sha256(path.read_bytes()).hexdigest() == digest, f"Unexpected contents: {name}")
    for name in ["LICENSE.txt", "MEDIA-LICENSE.md"]:
        require((resources / name).is_file() and "MIT" in (resources / name).read_text(), f"Missing license: {name}")
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    for key, expected in {
        "CFBundleIdentifier": "com.wallnetic.screensaver",
        "CFBundlePackageType": "BNDL",
        "CFBundleExecutable": "WallneticScreenSaver",
        "NSPrincipalClass": "WallneticScreenSaverView",
        "LSMinimumSystemVersion": "13.0",
    }.items():
        require(info.get(key) == expected, f"Unexpected {key}")
    require(re.fullmatch(r"\d+\.\d+\.\d+", info.get("CFBundleShortVersionString", "")), "Invalid version")
    require(re.fullmatch(r"[1-9]\d*", info.get("CFBundleVersion", "")), "Invalid build number")
    if resources_only:
        return info

    # Keep the distribution self-contained and free of accidental extra executables.
    allowed = {"Contents/Info.plist", "Contents/MacOS/WallneticScreenSaver",
               "Contents/_CodeSignature/CodeResources"}
    allowed |= {"Contents/Resources/" + name for name in set(ASSETS) | {"LICENSE.txt", "MEDIA-LICENSE.md"}}
    require({str(p.relative_to(bundle)) for p in bundle.rglob("*") if p.is_file()} == allowed,
            "Unexpected bundle payload")
    executable = bundle / "Contents/MacOS/WallneticScreenSaver"
    require(set(command("lipo", "-archs", str(executable)).stdout.split()) == {"arm64", "x86_64"},
            "Both native architectures are required")
    load_commands = command("otool", "-l", str(executable)).stdout
    require(re.findall(r"\bminos (\S+)", load_commands) == ["13.0", "13.0"], "Deployment target must be macOS 13")
    for line in command("otool", "-L", str(executable)).stdout.splitlines():
        if line.startswith("\t"):
            require(line.strip().startswith(("/System/Library/Frameworks/", "/usr/lib/")),
                    "Unexpected non-system dependency")
    command("codesign", "--verify", "--strict", "--all-architectures", str(bundle))
    entitlements = command("codesign", "--display", "--entitlements", "-", "--xml", str(bundle)).stdout.strip()
    require(not entitlements or not plistlib.loads(entitlements.encode()), "Candidate must not declare entitlements")
    if distribution:
        signature = command("codesign", "--display", "--verbose=4", str(bundle)).stderr
        require("Authority=Developer ID Application:" in signature, "Developer ID Application signature required")
        require("(runtime)" in signature and "Timestamp=" in signature,
                "Hardened runtime and secure timestamp required")
    return info


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--resources-only", action="store_true")
    parser.add_argument("--distribution", action="store_true")
    args = parser.parse_args()
    if args.resources_only and args.distribution:
        parser.error("Distribution validation must include code and signature checks")
    try:
        result = validate(args.bundle, args.resources_only, args.distribution)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Validation failed: {error}\n")
    print(f"Validated Wallnetic Screen Saver {result['CFBundleShortVersionString']} ({result['CFBundleVersion']})")
