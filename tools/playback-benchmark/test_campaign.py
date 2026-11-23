"""The session runner's planning and bookkeeping; no playback or collection."""
import argparse
import json
from pathlib import Path
import tempfile
import unittest

import campaign


class Result:
    def __init__(self, returncode):
        self.returncode = returncode


class CampaignTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.media = self.root / "media"
        self.media.mkdir()
        (self.media / "fixtures.json").write_text("{}")

    def arguments(self, **changes):
        values = {"media": self.media, "context": "Rig A; AC", "output": self.root / "session",
                  "warmup": 30.0, "seconds": 60.0, "repeats": 5, "cooldown": 60.0, "width": 960.0, "height": 540.0}
        values.update(changes)
        return argparse.Namespace(**values)

    def collector(self, codes, eligible=True, repeats=5):
        """A stand-in for `benchmark.py run`: writes records as the collector would."""
        calls = []

        def run(command):
            calls.append(command)
            code = codes[len(calls) - 1] if len(calls) <= len(codes) else 0
            folder = Path(command[command.index("--output") + 1])
            if code == 0:
                folder.mkdir()
                for repetition in range(1, repeats + 1):
                    (folder / f"{repetition:02d}.json").write_text(json.dumps({"eligible_for_baseline": eligible}))
            return Result(code)

        return run, calls

    # MARK: Plan

    def test_a_session_covers_both_fixtures_and_engines_and_avplayer_once_per_fixture(self):
        plan = campaign.configurations()
        self.assertEqual(len(plan), 8, "Two fixtures: three Metal profiles and one AVPlayer run each")
        self.assertEqual([item["name"] for item in plan[:4]],
                         ["h264-metal-quality-screens0", "h264-metal-balanced-screens0",
                          "h264-metal-battery-screens0", "h264-avplayer-balanced-screens0"])
        avplayer = [item for item in plan if item["engine"] == "avplayer"]
        self.assertEqual([item["profile"] for item in avplayer], ["balanced", "balanced"])
        self.assertEqual(len({item["name"] for item in plan}), len(plan), "Every configuration has its own folder")

    def test_overlays_screens_and_order_are_part_of_the_plan(self):
        plan = campaign.configurations(fixtures=("h264",), engines=("metal",), profiles=("balanced",),
                                       overlays=("none", "clock"), screens="0,1")
        self.assertEqual([item["name"] for item in plan],
                         ["h264-metal-balanced-screens0+1", "h264-metal-balanced-screens0+1-clock"])
        forward = campaign.configurations()
        self.assertEqual(campaign.configurations(reverse=True), list(reversed(forward)))

    def test_the_estimate_counts_every_repetition_and_the_pauses_between(self):
        self.assertEqual(campaign.estimate_seconds(0, 30, 60, 5, 60), 0)
        self.assertEqual(campaign.estimate_seconds(1, 30, 60, 5, 60), 5 * 95)
        self.assertEqual(campaign.estimate_seconds(8, 30, 60, 5, 60), 8 * 5 * 95 + 7 * 60)
        text = campaign.describe(campaign.configurations(), 30, 60, 5, 60)
        self.assertIn("8 configuration(s)", text)
        self.assertIn("About 70 minutes", text)

    # MARK: Run

    def test_a_session_collects_every_configuration_and_records_it(self):
        plan = campaign.configurations(fixtures=("h264",))
        runner, calls = self.collector([])
        pauses, lines = [], []
        code = campaign.run(self.arguments(), plan, runner=runner, sleep=pauses.append, log=lines.append)
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 4)
        self.assertEqual(pauses, [60.0, 60.0, 60.0], "A pause between configurations, none before the first")
        command = calls[0]
        self.assertEqual(command[2], "run")
        for flag, value in [("--fixture", "h264"), ("--engine", "metal"), ("--profile", "quality"),
                            ("--overlay", "none"), ("--screens", "0"), ("--repeats", "5"),
                            ("--warmup", "30"), ("--seconds", "60"), ("--context", "Rig A; AC")]:
            self.assertEqual(command[command.index(flag) + 1], value)
        record = json.loads((self.root / "session/campaign.json").read_text())
        self.assertEqual([item["status"] for item in record["configurations"]], ["collected"] * 4)
        self.assertEqual(record["configurations"][0]["eligible_records"], 5)
        self.assertIsNotNone(record["finished"])
        self.assertEqual(record["sampling"]["repeats"], 5)

    def test_a_failed_configuration_is_recorded_and_the_session_goes_on(self):
        plan = campaign.configurations(fixtures=("h264",))
        runner, calls = self.collector([0, 1])
        code = campaign.run(self.arguments(), plan, runner=runner, sleep=lambda _: None, log=lambda _: None)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 4, "The configurations after the failure still run")
        record = json.loads((self.root / "session/campaign.json").read_text())
        self.assertEqual([item["status"] for item in record["configurations"]],
                         ["collected", "failed", "collected", "collected"])
        self.assertEqual(record["configurations"][1]["records"], 0)

    def test_records_that_are_not_eligible_do_not_count_as_a_baseline(self):
        plan = campaign.configurations(fixtures=("h264",), engines=("avplayer",))
        runner, _ = self.collector([], eligible=False)
        code = campaign.run(self.arguments(), plan, runner=runner, sleep=lambda _: None, log=lambda _: None)
        self.assertEqual(code, 0, "Collected, so not a failure of the session")
        record = json.loads((self.root / "session/campaign.json").read_text())
        self.assertEqual(record["configurations"][0]["status"], "collected, not all eligible")
        self.assertEqual(record["configurations"][0]["eligible_records"], 0)

    def test_an_interrupted_session_keeps_what_it_has(self):
        plan = campaign.configurations(fixtures=("h264",))
        runner, calls = self.collector([])

        def interrupt(_):
            raise KeyboardInterrupt

        code = campaign.run(self.arguments(), plan, runner=runner, sleep=interrupt, log=lambda _: None)
        self.assertEqual(code, 130)
        self.assertEqual(len(calls), 1)
        record = json.loads((self.root / "session/campaign.json").read_text())
        self.assertTrue(record["interrupted"])
        self.assertEqual([item["status"] for item in record["configurations"]],
                         ["collected", "not run", "not run", "not run"])

    def test_results_are_never_overwritten(self):
        (self.root / "session").mkdir()
        with self.assertRaises(FileExistsError):
            campaign.run(self.arguments(), campaign.configurations(), runner=self.collector([])[0],
                         sleep=lambda _: None, log=lambda _: None)

    # MARK: Command line

    def test_plan_prints_and_changes_nothing(self):
        self.assertEqual(campaign.main(["plan", "--fixtures", "h264", "--engines", "metal"]), 0)
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ["media"])

    def test_bad_choices_are_refused(self):
        for arguments in (["plan", "--fixtures", "vp9"], ["plan", "--screens", "0,0"],
                          ["plan", "--profiles", "quality,quality"], ["plan", "--warmup", "-1"]):
            with self.assertRaises(SystemExit):
                campaign.main(arguments)


if __name__ == "__main__":
    unittest.main()
