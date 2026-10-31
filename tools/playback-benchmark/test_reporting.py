"""Checks against misleading benchmark summaries; no playback or hardware tests."""
import copy
import json
from pathlib import Path
import subprocess
import sys
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
            with self.assertRaisesRegex(ValueError, "Invalid CPU|Non-finite JSON"):
                benchmark.summarize(paths)
            paths = self.write()
            self.mutate(paths[-1], lambda record: record.update(elapsed_seconds=value))
            with self.assertRaisesRegex(ValueError, "Invalid duration|Non-finite JSON"):
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

    def test_eligibility_flags_require_real_booleans(self):
        for field in ("eligible_for_baseline", "compiled_inputs_dirty"):
            for value in ("false", "true", 0, 1, None, []):
                with self.subTest(field=field, value=value):
                    paths = self.write()
                    self.mutate(paths[-1], lambda record: record.update({field: value}))
                    with self.assertRaises(ValueError):
                        benchmark.summarize(paths)
        self.record["eligible_for_baseline"] = False
        self.assertFalse(benchmark.summarize(self.write())["eligible_for_baseline"])

    def test_unavailable_metric_cannot_hide_an_invalid_repetition(self):
        for metric in ("footprint_peak_sampled_bytes", "footprint_mean_sampled_bytes",
                       "package_idle_wakeups_per_second", "interrupt_wakeups_per_second"):
            for invalid in (-1, float("nan"), float("inf"), True, "0", [], 10 ** 400):
                with self.subTest(metric=metric, invalid=invalid):
                    paths = self.write()
                    self.mutate(paths[0], lambda record: record["metrics"].update({metric: None}))
                    self.mutate(paths[-1], lambda record: record["metrics"].update({metric: invalid}))
                    with self.assertRaises(ValueError):
                        benchmark.summarize(paths)

    def test_booleans_are_not_numeric_measurements(self):
        changes = [lambda record: record["metrics"].update(cpu_percent_one_core=True)]
        changes += [lambda record, field=field: record.update({field: True})
                    for field in ("elapsed_seconds", "requested_seconds", "warmup_seconds", "sampling_interval_seconds")]
        for change in changes:
            paths = self.write()
            self.mutate(paths[-1], change)
            with self.assertRaises(ValueError):
                benchmark.summarize(paths)

    def test_malformed_record_fields_fail_cleanly(self):
        changes = [lambda record: record.pop("metrics"),
                   lambda record: record["metrics"].pop("interrupt_wakeups_per_second")]
        changes += [lambda record, field=field, value=value: record.update({field: value})
                    for field, value in (("id", []), ("id", " "), ("metrics", []),
                        ("invalid_reasons", "failure"), ("invalid_reasons", [None]),
                        ("schema_version", True), ("hardware", None), ("power_end", {}),
                        ("context", " "), ("window_points", [True, 540]),
                        ("screen_indices", [0, 0]), ("connected_screens", []))]
        for change in changes:
            paths = self.write()
            self.mutate(paths[-1], change)
            with self.assertRaises(ValueError):
                benchmark.summarize(paths)
        for value in ([], None, "record", 1):
            path = self.root / "invalid.json"
            path.write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                benchmark.summarize([path])

    def test_cli_rejects_ambiguous_or_nonfinite_json_without_a_traceback(self):
        good = json.dumps(self.record)
        for text in (good.replace('"eligible_for_baseline": true',
                                 '"eligible_for_baseline": false, "eligible_for_baseline": true'),
                     good.replace('"cpu_percent_one_core": 10', '"cpu_percent_one_core": NaN'),
                     good.replace('"cpu_percent_one_core": 10', '"cpu_percent_one_core": 1e400'),
                     '[]', '{"incomplete":'):
            path = self.root / "invalid-cli.json"
            path.write_text(text)
            result = subprocess.run([sys.executable, str(benchmark.HERE / "benchmark.py"),
                                     "summarize", str(path)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertIn("Benchmark failed:", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    def test_fixture_duration_must_be_a_finite_number(self):
        media = {"width": 1920, "height": 1080, "fps": 30, "codec_fourcc": "avc1", "duration_seconds": 10}
        for value in (float("nan"), float("inf"), None, True, "10", [], 10 ** 400):
            with self.subTest(value=value), self.assertRaises(ValueError):
                benchmark.verify_fixture("h264", dict(media, duration_seconds=value))

    def test_finite_large_values_do_not_overflow_summary_statistics(self):
        paths = self.write(6)
        for path in paths:
            self.mutate(path, lambda record: record["metrics"].update(cpu_percent_one_core=1e308))
        report = benchmark.summarize(paths)
        self.assertEqual(report["metrics"]["cpu_percent_one_core"]["median"], 1e308)
        json.dumps(report, allow_nan=False)


if __name__ == "__main__":
    unittest.main()
