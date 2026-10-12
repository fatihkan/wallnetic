"""Checks against misleading benchmark summaries; no playback or hardware tests."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import benchmark


class ReportingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.record = {
            "schema_version": 1, "scope": "isolated_renderer_host", "id": "run-0",
            "hardware": {"model": "test-machine"}, "os": {"build": "test-os"},
            "engine": "metal", "profile": "balanced", "warmup_seconds": 30, "requested_seconds": 60,
            "elapsed_seconds": 60.1, "window_points": [960, 540], "screen_indices": [0],
            "connected_screens": [{"id": 1, "scale": 2}], "fixture": {"sha256": "test-fixture"},
            "power_start": {"power_source": "AC Power"}, "power_end": {"power_source": "AC Power"},
            "build": {"binaries": {"PlaybackBenchmark": "test-binary"}}, "git_revision": "test-revision",
            "compiled_inputs_dirty": False, "activity_policy": "userInitiatedAllowingIdleSystemSleep",
            "sampling_interval_seconds": 1, "context": "test rig, quiet room", "eligible_for_baseline": True,
            "invalid_reasons": [], "metrics": {"cpu_percent_one_core": 10, "footprint_peak_sampled_bytes": 1000,
                "footprint_mean_sampled_bytes": 900, "package_idle_wakeups_per_second": None,
                "interrupt_wakeups_per_second": 3},
        }

    def write(self, count=5):
        paths = []
        for i in range(count):
            record = copy.deepcopy(self.record)
            record["id"] = f"run-{i}"
            record["metrics"]["cpu_percent_one_core"] = [10, 12, 11, 10, 100][i % 5]
            path = self.root / f"{i}.json"
            path.write_text(json.dumps(record))
            paths.append(path)
        return paths

    def mutate(self, path, change):
        record = json.loads(path.read_text())
        change(record)
        path.write_text(json.dumps(record))

    def test_five_comparable_runs_keep_spread_and_unavailable_metrics(self):
        report = benchmark.summarize(self.write())
        self.assertTrue(report["eligible_for_baseline"])
        self.assertEqual(report["metrics"]["cpu_percent_one_core"],
                         {"median": 11, "median_absolute_deviation": 1, "min": 10, "max": 100})
        self.assertIsNone(report["metrics"]["package_idle_wakeups_per_second"])
        self.assertIsNone(report["regression_thresholds"])
        self.assertEqual(report["full_app_device_validation"], "not_performed")

    def test_short_or_insufficient_runs_are_not_a_baseline(self):
        self.assertFalse(benchmark.summarize(self.write(1))["eligible_for_baseline"])
        self.record.update(warmup_seconds=1, requested_seconds=2, elapsed_seconds=2.1)
        self.assertFalse(benchmark.summarize(self.write())["eligible_for_baseline"])

    def test_mixed_configurations_are_rejected(self):
        for key, value in [("profile", "quality"), ("git_revision", "different-commit"),
                           ("fixture", {"sha256": "different-media"}), ("screen_indices", [0, 1]),
                           ("power_start", {"power_source": "Battery Power"}),
                           ("build", {"binaries": {"PlaybackBenchmark": "different-binary"}})]:
            with self.subTest(field=key):
                paths = self.write()
                self.mutate(paths[-1], lambda record: record.update({key: value}))
                with self.assertRaisesRegex(ValueError, "Incompatible"):
                    benchmark.summarize(paths)

    def test_duplicate_runs_cannot_inflate_repetition_count(self):
        path = self.write(1)[0]
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            benchmark.summarize([path] * 5)

    def test_interrupted_run_is_not_summarized(self):
        paths = self.write()
        self.mutate(paths[-1], lambda record: record.update(elapsed_seconds=3))
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            benchmark.summarize(paths)

    def test_bad_conditions_do_not_pass_minimum_collection_rules(self):
        for change in [lambda record: record.update(invalid_reasons=["window reported occluded or hidden"]),
                       lambda record: record.update(power_end={"power_source": "Battery Power"})]:
            paths = self.write()
            self.mutate(paths[-1], change)
            self.assertFalse(benchmark.summarize(paths)["eligible_for_baseline"])

    def test_nonfinite_values_are_rejected(self):
        for value in [float("nan"), float("inf"), -1]:
            paths = self.write()
            self.mutate(paths[-1], lambda record: record["metrics"].update(cpu_percent_one_core=value))
            with self.assertRaisesRegex(ValueError, "Invalid CPU"):
                benchmark.summarize(paths)
            paths = self.write()
            self.mutate(paths[-1], lambda record: record.update(elapsed_seconds=value))
            with self.assertRaisesRegex(ValueError, "Invalid duration"):
                benchmark.summarize(paths)
        for value in ["nan", "inf", "-1", "601"]:
            with self.assertRaises(Exception):
                benchmark.finite_range(1, 600)(value)

    def test_fixture_fallback_is_rejected(self):
        media = {"width": 3840, "height": 2160, "fps": 60, "codec_fourcc": "hvc1", "duration_seconds": 10}
        benchmark.verify_fixture("hevc", media)
        for key, value in [("width", 1920), ("fps", 30), ("codec_fourcc", "avc1"), ("duration_seconds", 5)]:
            with self.subTest(field=key), self.assertRaises(ValueError):
                benchmark.verify_fixture("hevc", dict(media, **{key: value}))

    def test_results_are_never_overwritten(self):
        path = self.root / "result.json"
        benchmark.save(path, {"preserved": True})
        with self.assertRaises(FileExistsError):
            benchmark.save(path, {"preserved": False})
        self.assertTrue(json.loads(path.read_text())["preserved"])


if __name__ == "__main__":
    unittest.main()
