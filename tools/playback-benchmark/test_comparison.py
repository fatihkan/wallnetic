"""Recorded-session comparisons only; no playback, collection or hardware claims."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import benchmark


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.record = {
            "schema_version": 1, "scope": "isolated_renderer_host", "id": "unused",
            "hardware": {"model": "fixture-machine"}, "os": {"build": "fixture-os"},
            "engine": "metal", "profile": "balanced", "warmup_seconds": 30, "requested_seconds": 60,
            "elapsed_seconds": 60.1, "window_points": [960, 540], "screen_indices": [0],
            "connected_screens": [{"id": 1, "scale": 2}], "fixture": {"sha256": "a" * 64},
            "power_start": {"power_source": "AC Power"}, "power_end": {"power_source": "AC Power"},
            "build": {"schema_version": 1, "compiler": "fixture compiler", "architecture": "arm64",
                      "sdk": "26.4", "optimization": "-O", "deployment_target": "13.0",
                      "inputs": {name: "b" * 64 for name in benchmark.COLLECTOR_INPUTS},
                      "binaries": {"PlaybackBenchmark": "c" * 64}},
            "git_revision": "baseline-commit", "compiled_inputs_dirty": False,
            "activity_policy": "userInitiatedAllowingIdleSystemSleep", "sampling_interval_seconds": 1,
            "context": "Fixture rig, identical background workloads", "eligible_for_baseline": True,
            "invalid_reasons": [], "metrics": {"cpu_percent_one_core": 10,
                "footprint_peak_sampled_bytes": 1000, "footprint_mean_sampled_bytes": 900,
                "package_idle_wakeups_per_second": None, "interrupt_wakeups_per_second": 3},
        }

    def session(self, name, values=(10, 10, 10, 10, 10), change=None):
        directory = self.root / name
        directory.mkdir(exist_ok=True)
        paths = []
        for index, value in enumerate(values):
            record = copy.deepcopy(self.record)
            record["id"] = f"{name}-{index}"
            record["metrics"]["cpu_percent_one_core"] = value
            if name == "candidate":
                record["git_revision"] = "candidate-commit"
                record["build"]["binaries"]["PlaybackBenchmark"] = "d" * 64
                record["build"]["inputs"]["src/Wallnetic/Engine/MetalVideoRenderer.swift"] = "e" * 64
            if change:
                change(record)
            path = directory / f"{index}.json"
            path.write_text(json.dumps(record))
            paths.append(path)
        return paths

    def mutate(self, path, change):
        record = json.loads(path.read_text())
        change(record)
        path.write_text(json.dumps(record))

    def test_builds_stay_separate_with_correct_deltas_units_and_dispersion(self):
        baseline = self.session("baseline", (8, 10, 10, 12, 100))
        candidate = self.session("candidate", (4, 5, 6, 7, 8))
        with patch.object(benchmark, "execute", side_effect=AssertionError("No external commands allowed")):
            result = benchmark.compare(baseline, candidate)
        cpu = result["metrics"]["cpu_percent_one_core"]
        self.assertEqual(cpu["baseline"], {"median": 10, "median_absolute_deviation": 2, "min": 8, "max": 100})
        self.assertEqual(cpu["candidate"], {"median": 6, "median_absolute_deviation": 1, "min": 4, "max": 8})
        self.assertEqual(cpu["absolute_change"], -4)
        self.assertEqual(cpu["relative_change_percent"], -40)
        self.assertEqual(cpu["unit"], "percent_of_one_logical_core")
        self.assertEqual(result["metrics"]["footprint_peak_sampled_bytes"]["unit"], "bytes")
        self.assertEqual(result["metrics"]["interrupt_wakeups_per_second"]["unit"], "wakeups_per_second")
        self.assertEqual(result["baseline"]["configuration"]["git_revision"], "baseline-commit")
        self.assertEqual(result["candidate"]["configuration"]["git_revision"], "candidate-commit")
        self.assertEqual(result["baseline"]["run_count"], 5)
        self.assertTrue(result["eligible_for_comparison"])
        self.assertEqual(result["performance_conclusion"], "not_assessed")
        self.assertIsNone(result["regression_thresholds"])
        self.assertEqual(result["full_app_device_validation"], "not_performed")
        reverse = benchmark.compare(candidate, baseline)["metrics"]["cpu_percent_one_core"]
        self.assertEqual(reverse["absolute_change"], 4)
        self.assertAlmostEqual(reverse["relative_change_percent"], 100 * 4 / 6)

    def test_same_build_independent_sessions_can_measure_noise(self):
        result = benchmark.compare(self.session("session-one"), self.session("session-two"))
        self.assertTrue(result["eligible_for_comparison"])
        self.assertEqual(result["metrics"]["cpu_percent_one_core"]["absolute_change"], 0)

    def test_different_conditions_are_rejected_instead_of_comparing(self):
        changes = {"hardware": {"model": "other-rig"}, "os": {"build": "other-os"},
                   "engine": "avplayer", "profile": "quality", "warmup_seconds": 31,
                   "requested_seconds": 59, "window_points": [800, 450], "screen_indices": [1],
                   "connected_screens": [{"id": 1, "scale": 1}], "fixture": {"sha256": "f" * 64},
                   "power_start": {"power_source": "Battery Power"}, "context": "Different workload",
                   "activity_policy": "different activity", "sampling_interval_seconds": 2}
        baseline = self.session("baseline")
        for field, value in changes.items():
            with self.subTest(field=field):
                candidate = self.session("candidate", change=lambda record: record.update({field: value}))
                with self.assertRaisesRegex(ValueError, f"Incompatible comparison conditions: {field}"):
                    benchmark.compare(baseline, candidate)
        candidate = self.session("candidate", change=lambda record: record.update(connected_screens=[{"id": True, "scale": 2}]))
        with self.assertRaisesRegex(ValueError, "connected_screens"):
            benchmark.compare(baseline, candidate)

    def test_toolchain_and_collector_changes_are_rejected(self):
        baseline = self.session("baseline")
        changes = [lambda record, field=field: record["build"].update({field: "different"})
                   for field in benchmark.TOOLCHAIN_FIELDS]
        changes += [lambda record, name=name: record["build"]["inputs"].update({name: "f" * 64})
                    for name in benchmark.COLLECTOR_INPUTS]
        for change in changes:
            with self.assertRaisesRegex(ValueError, "Incompatible collector or toolchain"):
                benchmark.compare(baseline, self.session("candidate", change=change))

    def test_missing_or_malformed_method_metadata_is_not_assumed_compatible(self):
        changes = [lambda record: record["build"].pop("compiler"),
                   lambda record: record["build"].update(sdk=True),
                   lambda record: record["build"].update(inputs=[]),
                   lambda record: record["build"]["inputs"].pop(benchmark.COLLECTOR_INPUTS[0]),
                   lambda record: record["build"]["inputs"].update({benchmark.COLLECTOR_INPUTS[0]: "unknown"})]
        for change in changes:
            # Even matching malformed metadata must be rejected on both sides.
            with self.assertRaisesRegex(ValueError, "Missing|invalid"):
                benchmark.compare(self.session("baseline", change=change), self.session("candidate", change=change))

    def test_overlay_is_the_compared_treatment_and_is_reported(self):
        report = benchmark.compare(self.session("baseline"),
                                   self.session("candidate", change=lambda record: record.update(overlay="clock")))
        self.assertEqual(report["treatment"], {"overlay": {"baseline": "none", "candidate": "clock"}})
        self.assertTrue(report["eligible_for_comparison"])

    def test_records_from_before_the_overlay_condition_count_as_none(self):
        baseline = self.session("baseline", change=lambda record: record.pop("overlay", None))
        report = benchmark.compare(baseline, self.session("candidate"))
        self.assertEqual(report["treatment"]["overlay"], {"baseline": "none", "candidate": "none"})

    def test_one_session_cannot_mix_overlay_conditions(self):
        paths = self.session("baseline")
        self.mutate(paths[0], lambda record: record.update(overlay="clock"))
        with self.assertRaisesRegex(ValueError, "Incompatible runs"):
            benchmark.summarize(paths)
        self.mutate(paths[0], lambda record: record.update(overlay="sparkles"))
        with self.assertRaisesRegex(ValueError, "Invalid overlay condition"):
            benchmark.summarize(paths)

    def test_one_collector_builds_the_baseline_and_later_revisions(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(benchmark, "APP", Path(directory)):
            self.assertEqual(benchmark.renderer_sources(), benchmark.RENDERER_SOURCES)
            for name in benchmark.OPTIONAL_RENDERER_SOURCES:
                (Path(directory) / name).parent.mkdir(parents=True, exist_ok=True)
                (Path(directory) / name).write_text("// later revision")
            self.assertEqual(benchmark.renderer_sources(),
                             benchmark.RENDERER_SOURCES + benchmark.OPTIONAL_RENDERER_SOURCES)

    def test_overlapping_run_ids_are_not_independent_comparisons(self):
        baseline, candidate = self.session("baseline"), self.session("candidate")
        self.mutate(candidate[-1], lambda record: record.update(id="baseline-0"))
        with self.assertRaisesRegex(ValueError, "Duplicate run ID across"):
            benchmark.compare(baseline, candidate)

    def test_comparison_does_not_relax_validation_within_either_session(self):
        for name in ("baseline", "candidate"):
            baseline, candidate = self.session("baseline"), self.session("candidate")
            paths = baseline if name == "baseline" else candidate
            self.mutate(paths[-1], lambda record: record.update(git_revision="third-build"))
            with self.assertRaisesRegex(ValueError, "Incompatible runs"):
                benchmark.compare(baseline, candidate)
            self.mutate(paths[-1], lambda record: record["metrics"].update(cpu_percent_one_core=True))
            with self.assertRaisesRegex(ValueError, "Invalid CPU"):
                benchmark.compare(baseline, candidate)

    def test_unavailable_metric_preserves_available_side_without_partial_average(self):
        baseline = self.session("baseline")
        candidate = self.session("candidate")
        self.mutate(baseline[0], lambda record: record["metrics"].update(footprint_mean_sampled_bytes=None))
        value = benchmark.compare(baseline, candidate)["metrics"]["footprint_mean_sampled_bytes"]
        self.assertIsNone(value["baseline"])
        self.assertEqual(value["candidate"]["median"], 900)
        self.assertIsNone(value["absolute_change"])
        self.assertIsNone(value["relative_change_percent"])
        self.assertEqual(value["relative_change_status"], "unavailable")

    def test_zero_baseline_and_extreme_ratio_never_create_nonfinite_json(self):
        for before, after, status in ((0, 0, "zero_baseline"), (0, 10, "zero_baseline"),
                                      (1e-308, 1e308, "outside_finite_range")):
            report = benchmark.compare(self.session("baseline", [before] * 5), self.session("candidate", [after] * 5))
            value = report["metrics"]["cpu_percent_one_core"]
            self.assertEqual(value["absolute_change"], after - before)
            self.assertIsNone(value["relative_change_percent"])
            self.assertEqual(value["relative_change_status"], status)
            json.dumps(report, allow_nan=False)

    def test_short_dirty_or_invalid_sessions_never_receive_a_performance_pass(self):
        cases = [({"warmup_seconds": 1, "requested_seconds": 2}, {}, "minimum baseline"),
                 ({}, {"compiled_inputs_dirty": True}, "uncommitted"),
                 ({}, {"invalid_reasons": ["sampling stalled"]}, "minimum baseline"),
                 ({}, {"power_end": {"power_source": "Battery Power"}}, "minimum baseline")]
        for shared, candidate_only, reason in cases:
            baseline = self.session("baseline", change=lambda record: record.update(shared))
            candidate = self.session("candidate", change=lambda record: record.update(shared, **candidate_only))
            report = benchmark.compare(baseline, candidate)
            self.assertFalse(report["eligible_for_comparison"])
            self.assertTrue(any(reason in issue for issue in report["eligibility_issues"]))
            self.assertEqual(report["performance_conclusion"], "not_assessed")
            self.assertIsNone(report["regression_thresholds"])
        report = benchmark.compare(self.session("baseline", [10]), self.session("candidate", [10]))
        self.assertFalse(report["eligible_for_comparison"])

    def test_cli_success_is_read_only_and_matches_the_api(self):
        baseline, candidate = self.session("baseline"), self.session("candidate")
        original = {path: path.read_bytes() for path in baseline + candidate}
        result = subprocess.run([sys.executable, str(benchmark.HERE / "benchmark.py"), "compare",
                                 "--baseline", *map(str, baseline), "--candidate", *map(str, candidate)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), benchmark.compare(baseline, candidate))
        self.assertEqual(result.stderr, "")
        self.assertEqual({path: path.read_bytes() for path in original}, original)

    def test_cli_failure_has_no_partial_report_or_traceback(self):
        baseline, candidate = self.session("baseline"), self.session("candidate")
        candidate[-1].write_text('{"id": "duplicated", "id": "ambiguous"}')
        result = subprocess.run([sys.executable, str(benchmark.HERE / "benchmark.py"), "compare",
                                 "--baseline", *map(str, baseline), "--candidate", *map(str, candidate)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("Duplicate JSON key", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
