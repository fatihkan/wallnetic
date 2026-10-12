# Playback benchmark tools

See [the protocol and pending device matrix](../../docs/PLAYBACK_BENCHMARKS.md).

```sh
python3 tools/playback-benchmark/benchmark.py build
python3 -m unittest discover -s tools/playback-benchmark -p 'test_*.py'
```

These two commands compile the real renderers and check result handling. They do
not open playback windows, generate media, run a benchmark or alter the installed
app. `fixtures` and `run` are explicit opt-in commands documented in the protocol.
