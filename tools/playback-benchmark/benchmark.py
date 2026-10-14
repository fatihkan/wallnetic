#!/usr/bin/env python3
"""Build real renderers, generate original fixtures, collect and summarize runs.

No third-party Python packages, shell interpolation, app preferences, or privileged tools.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import statistics
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BUILD = ROOT / ".build/playback-benchmark"
APP = ROOT / "src/Wallnetic"
RENDERER_SOURCES = [
    "Engine/VideoRenderer.swift", "Engine/MetalVideoRenderer.swift",
    "Engine/RendererPlaybackMonitor.swift", "Engine/WallpaperVisibilityPolicy.swift",
    "Engine/WallpaperAspectFill.swift", "Models/PlaybackStatus.swift",
    "Services/PerformanceManager.swift", "Utils/Log.swift",
]
RECIPES = {"h264": (1920, 1080, 30, "avc1"), "hevc": (3840, 2160, 60, "hvc1")}
COMPARISON_FIELDS = (
    "schema_version", "scope", "hardware", "os", "engine", "profile", "warmup_seconds", "requested_seconds",
    "window_points", "screen_indices", "connected_screens", "fixture", "power_start", "build", "git_revision",
    "compiled_inputs_dirty", "activity_policy", "sampling_interval_seconds", "context",
)
SUMMARY_METRICS = ("cpu_percent_one_core", "footprint_peak_sampled_bytes", "footprint_mean_sampled_bytes",
                   "package_idle_wakeups_per_second", "interrupt_wakeups_per_second")


def execute(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, text=True, **kwargs)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def save(path, value):
    with Path(path).open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")


def inputs():
    files = [APP / item for item in RENDERER_SOURCES]
    files += [APP / "Engine/DesktopWindowController.swift", APP / "project.yml", ROOT / "LICENSE"]
    files += [HERE / name for name in ("Runner.swift", "Generate.swift", "Metrics.c", "Metrics.h", "benchmark.py")]
    return {str(path.relative_to(ROOT)): digest(path) for path in files}


def build():
    BUILD.mkdir(parents=True, exist_ok=True)
    # Extract the exact shared protocol/conformances; never copy renderer logic.
    controller = (APP / "Engine/DesktopWindowController.swift").read_text()
    marker = "/// Controls the desktop-level window"
    if controller.count(marker) != 1:
        raise ValueError("Renderer protocol boundary changed; review the build adapter")
    bridge = controller.split(marker)[0]
    if "protocol WallpaperRenderer:" not in bridge or "class DesktopWindowController" in bridge:
        raise ValueError("Renderer protocol extraction failed")
    (BUILD / "Bridge.swift").write_text(bridge)
    sdk = execute(["xcrun", "--sdk", "macosx", "--show-sdk-path"], capture_output=True).stdout.strip()
    arch = platform.machine()
    if arch not in ("arm64", "x86_64"):
        raise ValueError("Native macOS arm64 or x86_64 host required")
    compiler = execute(["xcrun", "swiftc", "--version"], capture_output=True).stdout.strip()
    sdk_version = execute(["xcrun", "--sdk", "macosx", "--show-sdk-version"], capture_output=True).stdout.strip()
    flags = ["-O", "-swift-version", "5", "-sdk", sdk, "-target", f"{arch}-apple-macosx13.0"]
    execute(["xcrun", "clang", "-O2", "-Wall", "-Wextra", "-Werror", "-isysroot", sdk,
             "-arch", arch, "-mmacosx-version-min=13.0", "-c", HERE / "Metrics.c", "-o", BUILD / "Metrics.o"])
    execute(["xcrun", "swiftc", *flags, "-import-objc-header", HERE / "Metrics.h",
             *[APP / name for name in RENDERER_SOURCES], BUILD / "Bridge.swift", HERE / "Runner.swift",
             BUILD / "Metrics.o", "-framework", "IOKit", "-o", BUILD / "PlaybackBenchmark"])
    execute(["xcrun", "swiftc", *flags, "-parse-as-library", HERE / "Generate.swift", "-o", BUILD / "Generate"])
    project = (APP / "project.yml").read_text()
    metadata = {"schema_version": 1, "inputs": inputs(), "compiler": compiler, "architecture": arch,
                "sdk": sdk_version, "optimization": "-O", "deployment_target": "13.0",
                "app_version": re.search(r'MARKETING_VERSION:\s*"?([\d.]+)', project)[1],
                "app_build": re.search(r'CURRENT_PROJECT_VERSION:\s*"?(\d+)', project)[1],
                "binaries": {name: digest(BUILD / name) for name in ("PlaybackBenchmark", "Generate")}}
    # Rebuilding intentionally replaces only this tool's ignored build artifacts.
    (BUILD / "build.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    print(f"Built optimized host and fixture generator: {BUILD}")


def built():
    metadata = json.loads((BUILD / "build.json").read_text())
    if metadata["inputs"] != inputs() or any(digest(BUILD / name) != checksum for name, checksum in metadata["binaries"].items()):
        raise ValueError("Benchmark sources or binary changed; run the build command again")
    return metadata


def inspect(path):
    return json.loads(execute([BUILD / "PlaybackBenchmark", "--inspect", path], capture_output=True, timeout=45).stdout)


def verify_fixture(recipe, metadata):
    if not isinstance(metadata, dict) or not nonnegative_number(metadata.get("duration_seconds")):
        raise ValueError("Invalid fixture duration; expected a finite nonnegative number")
    width, height, fps, codec = RECIPES[recipe]
    if tuple(metadata.get(key) for key in ("width", "height", "fps", "codec_fourcc")) != (width, height, fps, codec):
        raise ValueError(f"Unexpected encoding for {recipe}; no automatic fallback")
    if abs(metadata["duration_seconds"] - 10) > 1 / fps:
        raise ValueError("Fixture must contain ten seconds of video")


def fixtures(directory):
    metadata = built()
    directory.mkdir(parents=True, exist_ok=False)
    entries = {}
    for recipe in RECIPES:
        path = directory / f"{recipe}.mp4"
        execute([BUILD / "Generate", recipe, path], timeout=370)
        entries[recipe] = inspect(path)
        verify_fixture(recipe, entries[recipe])
    (directory / "LICENSE").write_bytes((ROOT / "LICENSE").read_bytes())
    save(directory / "fixtures.json", {"schema_version": 1, "recipe_version": 1,
         "license": "MIT", "copyright": "2024-2026 Fatih Kan",
         "provenance": "Original procedural radial gradients; no downloaded footage, audio, or fonts",
         "generator_sha256": metadata["inputs"]["tools/playback-benchmark/Generate.swift"],
         "generator_build": metadata, "generation_os": platform.mac_ver()[0], "fixtures": entries})
    print(f"Prepared both fixtures and redistribution license: {directory}")


def run(args):
    metadata = built()
    manifest = json.loads((args.media / "fixtures.json").read_text())
    path = args.media / f"{args.fixture}.mp4"
    fixture = inspect(path)
    verify_fixture(args.fixture, fixture)
    if fixture != manifest["fixtures"][args.fixture]:
        raise ValueError("Fixture changed since generation; use an intact archived media set")
    args.output.mkdir(parents=True, exist_ok=False)
    revision = execute(["git", "-C", ROOT, "rev-parse", "HEAD"], capture_output=True).stdout.strip()
    dirty = execute(["git", "-C", ROOT, "status", "--porcelain", "--", *metadata["inputs"]], capture_output=True).stdout.strip()
    for repetition in range(1, args.repeats + 1):
        record_id = str(uuid.uuid4())
        with (args.output / f"{repetition:02d}.stderr.log").open("x") as log:
            result = execute([BUILD / "PlaybackBenchmark", args.engine, args.profile, path,
                              args.warmup, args.seconds, args.screens, args.width, args.height],
                             stdout=subprocess.PIPE, stderr=log, timeout=args.warmup + args.seconds + 90)
        record = json.loads(result.stdout)
        record.update({"id": record_id, "repetition": repetition, "build": metadata, "git_revision": revision,
                       "compiled_inputs_dirty": bool(dirty), "fixture_recipe": args.fixture,
                       "fixture_recipe_version": manifest["recipe_version"], "context": args.context})
        save(args.output / f"{repetition:02d}.json", record)
        print(f"Saved repetition {repetition}/{args.repeats}; baseline eligible: {record['eligible_for_baseline']}")
    save(args.output / "summary.json", summarize(sorted(args.output.glob("[0-9][0-9].json"))))


def comparable(record):
    # Revision/binary hash intentionally included: never average different builds.
    return {key: record[key] for key in COMPARISON_FIELDS}


def nonnegative_number(value):
    # bool subclasses int in Python; it is never a measured number.
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value) and value >= 0
    except OverflowError:
        return False


def read_record(path):
    def invalid_constant(_):
        raise ValueError("Non-finite JSON number in run record")

    def finite_float(value):
        number = float(value)
        if not math.isfinite(number):
            raise ValueError("Non-finite JSON number in run record")
        return number

    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON key in run record")
            result[key] = value
        return result

    return json.loads(path.read_text(), parse_constant=invalid_constant,
                      parse_float=finite_float, object_pairs_hook=unique_object)


def validate_record(record):
    """Validate the report inputs, not the authenticity of a measurement."""
    if not isinstance(record, dict):
        raise ValueError("Run record must be a JSON object")
    required = set(COMPARISON_FIELDS) | {"id", "elapsed_seconds", "power_end", "invalid_reasons",
                                       "eligible_for_baseline", "metrics"}
    missing = required - record.keys()
    if missing:
        raise ValueError("Missing run fields: " + ", ".join(sorted(missing)))
    if type(record["schema_version"]) is not int or record["schema_version"] != 1 or record["scope"] != "isolated_renderer_host":
        raise ValueError("Unsupported run schema or scope")
    for name in ("eligible_for_baseline", "compiled_inputs_dirty"):
        if type(record[name]) is not bool:
            raise ValueError(f"Invalid boolean flag: {name}")
    for name in ("id", "git_revision", "activity_policy", "context"):
        if not isinstance(record[name], str) or not record[name].strip():
            raise ValueError(f"Invalid text field: {name}")
    for name in ("hardware", "os", "fixture", "power_start", "power_end", "build"):
        if not isinstance(record[name], dict) or not record[name]:
            raise ValueError(f"Invalid configuration object: {name}")
    if record["engine"] not in ("metal", "avplayer") or record["profile"] not in ("quality", "balanced", "battery"):
        raise ValueError("Invalid renderer or playback profile")
    reasons = record["invalid_reasons"]
    if not isinstance(reasons, list) or any(not isinstance(reason, str) or not reason.strip() for reason in reasons):
        raise ValueError("Invalid failure reasons; expected an array of nonempty strings")
    points = record["window_points"]
    if not isinstance(points, list) or len(points) != 2 or any(not nonnegative_number(value) or value == 0 for value in points):
        raise ValueError("Invalid window dimensions")
    indices = record["screen_indices"]
    if (not isinstance(indices, list) or not indices
            or any(type(value) is not int or value < 0 for value in indices) or len(set(indices)) != len(indices)):
        raise ValueError("Invalid screen indices")
    screens = record["connected_screens"]
    if not isinstance(screens, list) or not screens or any(not isinstance(screen, dict) or not screen for screen in screens):
        raise ValueError("Invalid connected display configuration")
    interval = record["sampling_interval_seconds"]
    if not nonnegative_number(interval) or interval == 0:
        raise ValueError("Invalid sampling interval")
    for name in ("elapsed_seconds", "requested_seconds", "warmup_seconds"):
        if not nonnegative_number(record[name]):
            raise ValueError(f"Invalid duration: {name}")
    if record["elapsed_seconds"] < record["requested_seconds"] or record["requested_seconds"] < 1:
        raise ValueError("Incomplete measurement")
    metrics = record["metrics"]
    if not isinstance(metrics, dict) or any(name not in metrics for name in SUMMARY_METRICS):
        raise ValueError("Missing measurement fields; unavailable metrics must be explicit null values")
    for name in SUMMARY_METRICS:
        value = metrics[name]
        if value is None and name != "cpu_percent_one_core":
            continue
        if not nonnegative_number(value):
            label = "CPU measurement" if name == "cpu_percent_one_core" else f"metric: {name}"
            raise ValueError(f"Invalid {label}")


def finite_median(values):
    # Avoid overflow from adding two large finite nonnegative middle values.
    lower, upper = statistics.median_low(values), statistics.median_high(values)
    return lower if lower == upper else lower + (upper - lower) / 2


def summarize(paths):
    if not paths:
        raise ValueError("No run records provided")
    records = [read_record(path) for path in paths]
    for record in records:
        validate_record(record)
    key = comparable(records[0])
    ids = set()
    for record in records:
        if comparable(record) != key:
            raise ValueError("Incompatible runs: summarize each build/environment/fixture separately")
        if record["id"] in ids:
            raise ValueError("Duplicate run ID; copies are not independent repetitions")
        ids.add(record["id"])
    eligible = len(records) >= 5 and all(record["eligible_for_baseline"] and not record["invalid_reasons"]
        and record["warmup_seconds"] >= 30 and record["requested_seconds"] >= 60
        and record["power_start"] == record["power_end"] for record in records)
    metrics = {}
    for name in SUMMARY_METRICS:
        values = [record["metrics"][name] for record in records]
        if any(value is None for value in values):
            metrics[name] = None
            continue
        median = finite_median(values)
        metrics[name] = {"median": median, "median_absolute_deviation": finite_median([abs(value - median) for value in values]),
                         "min": min(values), "max": max(values)}
    return {"schema_version": 1, "scope": "isolated_renderer_host", "run_count": len(records),
            "run_ids": sorted(ids), "eligible_for_baseline": eligible, "configuration": key, "metrics": metrics,
            "invalid_reasons": sorted({reason for record in records for reason in record["invalid_reasons"]}),
            "regression_thresholds": None, "full_app_device_validation": "not_performed",
            "note": "Eligibility is a minimum collection rule, not a performance pass. Review traces and context; calibrate thresholds from repeated baseline sessions."}


def finite_range(low, high):
    def parse(value):
        number = float(value)
        if not math.isfinite(number) or not low <= number <= high:
            raise argparse.ArgumentTypeError(f"Expected finite number in [{low}, {high}]")
        return number
    return parse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("build", help="Compile optimized current renderers and fixture generator")
    fixture = commands.add_parser("fixtures", help="Generate standard media into a NEW directory")
    fixture.add_argument("directory", type=Path)
    collect = commands.add_parser("run", help="Explicitly open temporary playback windows and collect measurements")
    collect.add_argument("--media", type=Path, required=True)
    collect.add_argument("--fixture", choices=RECIPES, required=True)
    collect.add_argument("--engine", choices=("metal", "avplayer"), required=True)
    collect.add_argument("--profile", choices=("quality", "balanced", "battery"), required=True)
    collect.add_argument("--output", type=Path, required=True, help="New output directory; never overwrite results")
    collect.add_argument("--warmup", type=finite_range(0, 300), default=30)
    collect.add_argument("--seconds", type=finite_range(1, 600), default=60)
    collect.add_argument("--repeats", type=int, choices=range(1, 21), default=5)
    collect.add_argument("--screens", default="0", help="Distinct connected display indices, e.g. 0,1")
    collect.add_argument("--width", type=finite_range(64, 8192), default=960)
    collect.add_argument("--height", type=finite_range(64, 8192), default=540)
    collect.add_argument("--context", required=True, help="Machine label, background apps, brightness, ambient conditions; no private information")
    report = commands.add_parser("summarize", help="Summarize compatible raw JSON records; reject mixed configurations")
    report.add_argument("records", nargs="+", type=Path)
    args = parser.parse_args()
    if args.command == "build": build()
    elif args.command == "fixtures": fixtures(args.directory.resolve())
    elif args.command == "run":
        if not re.fullmatch(r"\d+(,\d+)*", args.screens) or len(set(args.screens.split(","))) != len(args.screens.split(",")):
            parser.error("--screens must contain distinct nonnegative indices")
        if not args.context.strip(): parser.error("--context cannot be empty")
        args.media = args.media.resolve(); args.output = args.output.resolve()
        run(args)
    else: print(json.dumps(summarize(args.records), indent=2, sort_keys=True, allow_nan=False))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        print(f"Benchmark failed: {error}", file=sys.stderr)
        sys.exit(1)
