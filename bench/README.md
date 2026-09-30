# D3D Engine Benchmarks

Headless, zero-dependency benchmarks for the Ruby-side cost of the D3D engine.
Runs on system Ruby (no DragonRuby needed), like `tests/`.

## Usage

```bash
ruby bench/bench.rb                       # run all cases, compare to baseline
ruby bench/bench.rb --filter render/      # run a subset (substring match)
ruby bench/bench.rb --json                # machine-readable output
ruby bench/bench.rb --save                # write current results as the new baseline
ruby bench/bench.rb --fail-on-regression  # exit non-zero if any case is slower
ruby bench/bench.rb --no-baseline --quick # fast run, no baseline comparison
ruby bench/bench.rb --engine DIR          # benchmark app/d3d from another checkout
```

Each case reports minimum `ns/op` across rounds plus a noise band, and
allocated objects per op (CRuby only; deterministic). A change counts
as `faster`/`slower` only when it exceeds `max(noise band, 5%)`; otherwise it is
`within-noise`.

## Optimization loop (A/B, not stored baselines)

A stored baseline drifts with the machine's state: the same code once measured
~21% "faster" than `baseline.json` without any change. For decisions, compare
against a git revision on the same machine, interleaved:

```bash
ruby bench/evaluate.rb --base HEAD            # the one command: tests + golden + A/B
ruby bench/evaluate.rb --base HEAD --mruby    # + DragonRuby A/B + demo smoke test
ruby bench/evaluate.rb --base HEAD --mruby --native  # head side loads the C extension (D3D Pro)
```

`evaluate.rb` prints `DECISION: keep` only if all tests pass, the engine output
is unchanged, at least one case is faster, none is slower and no case
allocates more objects per op (`--json` for machine-readable output). With
`--mruby` a case that is only faster in DragonRuby counts too (e.g. a change to
an mruby-only code path), as long as nothing is slower in either runtime.

The building blocks:

| Tool | Purpose |
|---|---|
| `compare.rb [REV] [--filter X] [--pairs 3] [--mruby]` | A/B timing of the working tree vs `REV` (default `HEAD`). Runs base and head alternately in fresh processes (A B, B A, ...) and compares per pair ratios, so drift cancels. Both sides run this checkout's cases; only `app/` differs. Exit 2 if a case got slower. |
| `golden.rb` | Correctness guard: fingerprints the output of fixed scenes (`golden_scenes.rb`) against `golden.json`. `--against REV` compares the full output with a revision (float tolerance 1e-4); `--update` rewrites the fingerprints after an intended change. |
| `profile.rb CASE` | Exact per-op counts: allocation sites, method calls, executed engine lines. Deterministic, so reliable even when timing is noisy. |
| `smoke.rb` | Runs every demo headless in DragonRuby for 90 frames, reports exceptions and DragonRuby warnings, saves one screenshot per demo (with the C extension when `native/` is built). |
| `native_check.rb` | D3D Pro: renders fixed scenes in DragonRuby once with the Ruby fallback and once with the optional C extension (`bin/build-ext`) and requires identical output. |
| `mruby_runner.rb` | The benchmark cases inside DragonRuby (driven by `compare.rb --mruby`). |
| `OPTIMIZATION_LOG.md` | Every attempt, kept or rejected, plus a backlog of ideas. |


`bench.rb --save` / `baseline.json` remain as a rough long-term record only.

### DragonRuby

`compare.rb --mruby` and `smoke.rb` start DragonRuby with
`SDL_VIDEODRIVER=dummy` (no window). The binary is `DRAGONRUBY_BIN` or the
Smaug install matching `Smaug.toml` (`~/Library/Application
Support/org.Erebor-Studios.Smaug/dragonruby/<edition>-<version>/dragonruby`).
Code loaded by DragonRuby (`harness.rb`, `scenes.rb`, `cases/*`) must stay
mruby-compatible. `mruby_runner.rb` fixes mruby's GC mode (incremental, as the
demos use; `gc=generational` in `mruby_config.txt` for the default) so both
sides of an A/B run with the same GC, whatever their `app/main.rb` sets.

## Coverage

- `math/*` — Mat4 multiply, Vec3 ops, camera view matrix
- `render/*` — solid + textured cube grids, sphere field, voxel world rendering
- `voxel/*` — mesh rebuild, DDA raycast, AABB query
- `physics/*` — ray-model, sphere-model, voxel body movement

## Caveat: CRuby vs mruby

These benchmarks run on CRuby/MRI by default, but the game runs on DragonRuby's
mruby (about 2-3x slower per op). Algorithmic improvements and allocation
reductions transfer reliably across both; CRuby-specific micro-optimizations
may not. Confirm big wins with `compare.rb --mruby` / `evaluate.rb --mruby`.

## Stability

Each case reports the minimum per-op time across several rounds (the most
reproducible number for CPU microbenchmarks), with a time-based warmup so the
CPU settles before measuring. Even so, run-to-run variance on a laptop is real,
especially for the fastest cases. The 5% floor absorbs most of it. For a small
win near the floor, run the suite two or three times to confirm the verdict is
consistent before trusting it.
