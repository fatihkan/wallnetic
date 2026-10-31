# Playback benchmark tools

See [the protocol and pending device matrix](../../docs/PLAYBACK_BENCHMARKS.md).

```sh
python3 tools/playback-benchmark/benchmark.py build
python3 -m unittest discover -s tools/playback-benchmark -p 'test_*.py'
```

These two commands compile the real renderers and check result handling. They do
not open playback windows, generate media, run a benchmark or alter the installed
app. `fixtures` and `run` are explicit opt-in commands documented in the protocol.

Compare previously collected baseline and candidate sessions without starting playback:

```sh
python3 tools/playback-benchmark/benchmark.py compare \
  --baseline .build/benchmarks/baseline/[0-9][0-9].json \
  --candidate .build/benchmarks/candidate/[0-9][0-9].json
```

Use raw run records, not `summary.json`. The command keeps the two builds separate,
rejects different environments or measurement methods and reports median changes
with dispersion and units. Short or dirty-input sessions are marked ineligible.
It does not set regression thresholds or declare a performance pass. See the
protocol for unavailable metrics, zero baselines and the pending physical tests.
