#!/usr/bin/env python3
"""Run one whole measurement session: every renderer configuration in turn (#255).

  campaign.py plan [options]
      Print the configurations of a session and how long it takes.

  campaign.py run --media DIR --context TEXT --output NEW_DIR [options]
      Collect every configuration with `benchmark.py run`, pausing between
      them, and record what happened in NEW_DIR/campaign.json.

This file measures nothing. It calls the collector once per configuration and
keeps a log, so the collector and its build fingerprint stay as they are. A
configuration that fails is recorded and the session goes on with the next one.

No third-party Python packages and no shell interpolation.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
FIXTURES = ("h264", "hevc")
ENGINES = ("metal", "avplayer")
PROFILES = ("quality", "balanced", "battery")
OVERLAYS = ("none", "clock")
# AVPlayer plays at the video's own cadence in every profile, so one profile
# stands for all three.
AVPLAYER_PROFILE = "balanced"
# Time one repetition needs besides warmup and sampling: starting the host,
# reading the media and reaching the first frame.
STARTUP_SECONDS = 5


def configurations(fixtures=FIXTURES, engines=ENGINES, profiles=PROFILES, overlays=("none",), screens="0",
                   reverse=False):
    """The configurations of one session, in the order they are collected."""
    result = []
    for overlay in overlays:
        for fixture in fixtures:
            for engine in engines:
                for profile in (profiles if engine == "metal" else (AVPLAYER_PROFILE,)):
                    name = "-".join([fixture, engine, profile, "screens" + screens.replace(",", "+")])
                    if overlay != "none":
                        name += "-" + overlay
                    result.append({"name": name, "fixture": fixture, "engine": engine, "profile": profile,
                                   "overlay": overlay, "screens": screens})
    return list(reversed(result)) if reverse else result


def estimate_seconds(count, warmup, seconds, repeats, cooldown):
    """How long a session of `count` configurations takes, pauses included."""
    if count == 0:
        return 0
    return count * repeats * (warmup + seconds + STARTUP_SECONDS) + (count - 1) * cooldown


def describe(plan, warmup, seconds, repeats, cooldown):
    total = estimate_seconds(len(plan), warmup, seconds, repeats, cooldown)
    lines = [f"{len(plan)} configuration(s), {repeats} repetition(s) each: "
             f"{warmup:g} s warmup + {seconds:g} s sampling, {cooldown:g} s pause between configurations.",
             f"About {total / 60:.0f} minutes. The playback window must stay visible and uncovered for all of it."]
    lines += [f"  {index:2d}. {item['name']}" for index, item in enumerate(plan, 1)]
    return "\n".join(lines)


def collector_command(item, args, output):
    return [sys.executable, str(HERE / "benchmark.py"), "run",
            "--media", str(args.media), "--fixture", item["fixture"], "--engine", item["engine"],
            "--profile", item["profile"], "--overlay", item["overlay"], "--screens", item["screens"],
            "--warmup", f"{args.warmup:g}", "--seconds", f"{args.seconds:g}", "--repeats", str(args.repeats),
            "--width", f"{args.width:g}", "--height", f"{args.height:g}",
            "--context", args.context, "--output", str(output)]


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def eligible_records(directory):
    """(records saved, records eligible for a baseline) in one configuration's folder."""
    saved = eligible = 0
    for path in sorted(directory.glob("[0-9][0-9].json")):
        saved += 1
        try:
            eligible += json.loads(path.read_text()).get("eligible_for_baseline") is True
        except (OSError, ValueError):
            pass
    return saved, eligible


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def run(args, plan, runner=subprocess.run, sleep=time.sleep, log=print):
    """Collect every configuration. Returns 0 when all of them were collected."""
    args.output.mkdir(parents=True, exist_ok=False)
    session = {"schema_version": 1, "tool": "campaign.py", "started": now(), "finished": None,
               "context": args.context, "media": str(args.media),
               "sampling": {"warmup_seconds": args.warmup, "seconds": args.seconds, "repeats": args.repeats,
                            "cooldown_seconds": args.cooldown, "window_points": [args.width, args.height]},
               "configurations": [dict(item, status="not run") for item in plan]}
    record = args.output / "campaign.json"
    save(record, session)
    failed = 0
    try:
        for index, item in enumerate(session["configurations"]):
            if index:
                log(f"Pausing {args.cooldown:g} s before the next configuration.")
                sleep(args.cooldown)
            folder = args.output / item["name"]
            log(f"[{index + 1}/{len(plan)}] {item['name']}")
            item["started"] = now()
            code = runner(collector_command(item, args, folder)).returncode
            item["finished"] = now()
            item["exit_code"] = code
            item["records"], item["eligible_records"] = eligible_records(folder) if folder.is_dir() else (0, 0)
            # Collected, and every repetition is fit for a baseline?
            if code != 0:
                item["status"] = "failed"
                failed += 1
            elif item["eligible_records"] < args.repeats:
                item["status"] = "collected, not all eligible"
            else:
                item["status"] = "collected"
            save(record, session)
    except KeyboardInterrupt:
        session["interrupted"] = True
        log("Interrupted. Configurations that did not run are marked so.")
    session["finished"] = now()
    save(record, session)
    done = sum(item["status"] == "collected" for item in session["configurations"])
    log(f"{done} of {len(plan)} configuration(s) collected and eligible. Record: {record}")
    return 130 if session.get("interrupted") else (1 if failed else 0)


def choices(allowed):
    def parse(text):
        values = tuple(part for part in text.split(",") if part)
        unknown = [value for value in values if value not in allowed]
        if unknown or not values or len(set(values)) != len(values):
            raise argparse.ArgumentTypeError("choose distinct values from: " + ", ".join(allowed))
        return values
    return parse


def screens(text):
    parts = text.split(",")
    if not all(part.isdigit() for part in parts) or len(set(parts)) != len(parts):
        raise argparse.ArgumentTypeError("distinct display indices, for example 0 or 0,1")
    return text


def number(low, high):
    def parse(text):
        value = float(text)
        if not low <= value <= high:
            raise argparse.ArgumentTypeError(f"a number from {low:g} to {high:g}")
        return value
    return parse


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("plan", "run"):
        command = commands.add_parser(name)
        command.add_argument("--fixtures", type=choices(FIXTURES), default=FIXTURES)
        command.add_argument("--engines", type=choices(ENGINES), default=ENGINES)
        command.add_argument("--profiles", type=choices(PROFILES), default=PROFILES)
        command.add_argument("--overlays", type=choices(OVERLAYS), default=("none",))
        command.add_argument("--screens", type=screens, default="0")
        command.add_argument("--warmup", type=number(0, 300), default=30)
        command.add_argument("--seconds", type=number(1, 600), default=60)
        command.add_argument("--repeats", type=int, choices=range(1, 21), default=5)
        command.add_argument("--cooldown", type=number(0, 600), default=60,
                             help="Pause between configurations, so the machine cools")
        command.add_argument("--width", type=number(64, 8192), default=960)
        command.add_argument("--height", type=number(64, 8192), default=540)
        command.add_argument("--reverse", action="store_true",
                             help="Collect in the opposite order; alternate between sessions")
        if name == "run":
            command.add_argument("--media", type=Path, required=True)
            command.add_argument("--context", required=True,
                                 help="Machine label, background apps, brightness; no private information")
            command.add_argument("--output", type=Path, required=True, help="New directory; nothing is overwritten")
    args = parser.parse_args(argv)
    plan = configurations(args.fixtures, args.engines, args.profiles, args.overlays, args.screens, args.reverse)
    print(describe(plan, args.warmup, args.seconds, args.repeats, args.cooldown))
    if args.command == "plan":
        return 0
    if not args.context.strip():
        parser.error("--context cannot be empty")
    args.media = args.media.resolve()
    args.output = args.output.resolve()
    if not (args.media / "fixtures.json").is_file():
        parser.error("--media must be a folder made by `benchmark.py fixtures`")
    if args.output.exists():
        parser.error("--output must be a new directory")
    return run(args, plan)


if __name__ == "__main__":
    sys.exit(main())
