# Engine Benchmark Harness — Design

Date: 2026-06-15

## Purpose

Provide a repeatable way to measure the speed of the D3D engine so that an
AI-driven optimization loop can:

1. Run the benchmark and get stable, comparable numbers.
2. Detect whether a change made the engine faster, slower, or had no real effect
   (distinguished from run-to-run noise).
3. Check improvements against a committed baseline in a single run.

## Constraints & Context

- Runs **headless on system Ruby (CRuby/MRI)**, like the existing `tests/*.rb`.
  No DragonRuby runtime required.
- **Zero external gems** — matches the project's no-gem stance and the fact that
  DragonRuby ships no gem ecosystem.
- Key enabling fact: `Renderer.render` and `render_voxel_world` return a plain
  array of triangle hashes and never touch `args.outputs`. The entire Ruby-side
  cost we care about is pure computation, so it is fully measurable on system
  Ruby with **no DragonRuby stubbing**.
- The engine files already load under CRuby (the test suite proves this).

## Scope

Benchmarks cover all four engine areas:

- **Render pipeline** — `Renderer.render` and `Renderer.render_voxel_world`.
- **Math primitives** — `Vec3` / `Mat4` operations and `Camera` matrix builders.
- **Voxel world** — `build_mesh` / `rebuild!`, DDA raycast, `aabb_intersects?`.
- **Physics / collisions** — `ray_model` / `sphere_model`, `VoxelBody#move`.

Out of scope (may be added later): an in-game DragonRuby benchmark demo that
measures real frame times as ground truth.

## Architecture

```
bench/
  bench.rb        # CLI entry: load engine, run cases, time, compare, report
  harness.rb      # timing core: warmup, auto-calibration, median-of-rounds, noise band
  scenes.rb       # deterministic fixtures (cameras, model lists, voxel worlds)
  cases/
    render_bench.rb   # render pipeline cases
    math_bench.rb     # vec3 / mat4 / camera cases
    voxel_bench.rb    # voxel world cases
    physics_bench.rb  # collisions + voxel_body cases
  baseline.json   # committed baseline: ns/op + noise band per case
```

### Components

**`bench.rb` (runner / CLI)**
- Adds the repo root to `$LOAD_PATH`, then `require 'app/d3d/d3d.rb'` so the whole
  engine loads exactly as DragonRuby wires it (including `SCREEN_WIDTH` /
  `SCREEN_HEIGHT` constants), rather than a hand-picked subset of files.
- Requires the harness and all `cases/*.rb` files, which register their cases.
- Parses CLI flags, runs the selected cases through the harness, then reports.

**`harness.rb` (timing core)**
- Registry API: `Bench.case(name) { ... }` style, where each case provides:
  - `name` — unique string, namespaced by area (e.g. `render/cubes_grid_solid`).
  - `setup` proc — builds fixtures; **not timed**; result passed to the body.
  - `body` proc — the timed work; receives the setup result.
- Measurement procedure per case:
  1. **Warmup**: run the body a few times to trigger any lazy init / JIT-ish
     warmup and stabilize caches.
  2. **Auto-calibration**: scale the inner iteration count so one measured batch
     runs roughly 0.3–0.5s (avoids clock-resolution noise on fast cases without
     making slow cases take forever).
  3. **Rounds**: measure K rounds (default 5). `GC.start` before each round to
     reduce GC-pause variance.
  4. **Report stats**: median ns/op across rounds (robust to outlier GC pauses),
     plus a noise band derived from the round spread (e.g. relative
     min↔max or IQR).
- Timing source: `Process.clock_gettime(Process::CLOCK_MONOTONIC)`.

**`scenes.rb` (fixtures)**
- Deterministic, seeded fixture builders. Any randomness uses a fixed seed so
  every run benchmarks the identical workload.
- Built inside `setup` procs (not timed). Examples:
  - Camera(s) positioned to produce a realistic mix of visible / culled models.
  - Model lists: grids of solid and textured cubes/spheres.
  - A sizeable seeded voxel world with a terrain-like pattern.

### Coverage detail

- **render**: grids of solid + textured cubes and spheres, camera placed to
  exercise frustum culling, backface culling, and depth-sort paths; plus a
  `render_voxel_world` case over the seeded world.
- **math**: tight loops of `Mat4` multiply, `Vec3` ops, and `Camera#get_view_matrix`.
- **voxel**: `build_mesh` / `rebuild!` on the seeded world, a DDA raycast across
  it, and a batch of `aabb_intersects?` queries.
- **physics**: `ray_model` and `sphere_model` against a sphere mesh, and
  `VoxelBody#move` stepped over many frames against the seeded world.

## Comparison & Reporting

- **Default run**: loads `bench/baseline.json` if present. For each case computes
  `delta% = (current - baseline) / baseline * 100`. Verdict per case:
  - `faster` when delta is negative beyond the noise threshold,
  - `slower` when positive beyond the noise threshold,
  - `within-noise` when `|delta| <= max(measured noise band, floor)` where the
    floor is a small constant (e.g. 2%).
- **Output table** columns: `case | baseline ns/op | current ns/op | delta% | verdict`.
  Plus a one-line overall summary (counts of faster / slower / within-noise).
- **`--save`** — writes the current results as the new `baseline.json`
  (case name, ns/op, noise band).
- **`--json`** — machine-readable output for the AI loop to parse directly.
- **`--filter <substr>`** — run only cases whose name contains the substring.
- **`--fail-on-regression`** — exit non-zero if any case is `slower`, so the loop
  can gate on it. Default exit code is 0.

## Determinism / Noise Handling

- Fixed seeds for all fixtures → identical workload every run.
- Auto-calibration + median-of-rounds + per-round `GC.start` to keep variance
  low enough to detect small (3–8%) improvements.
- The reported noise band makes the floor of detectable change explicit, so the
  AI loop never treats jitter as a real win.

## Known Caveat (documented)

The harness measures **CRuby/MRI**, while the game runs on DragonRuby's **mruby**.
Algorithmic improvements and allocation reductions transfer reliably across both;
micro-optimizations tuned to CRuby may not. The benchmark README will state this
and recommend occasional in-game spot-checks as ground truth. An in-game
benchmark demo can be added later if needed.

## Testing

- The harness's pure logic (delta computation, verdict classification against a
  noise band, baseline load/save round-trip) gets unit tests under `tests/`,
  runnable with system Ruby like the existing suite.
- A smoke run (`ruby bench/bench.rb --filter <one-case>`) confirms the engine
  loads and at least one case produces a finite ns/op.

## Success Criteria

- `ruby bench/bench.rb` runs all cases headless on system Ruby and prints a
  results table.
- `ruby bench/bench.rb --save` writes a baseline; a subsequent run prints
  per-case deltas and verdicts against it.
- Repeated runs with no code change report all cases as `within-noise`.
- `--json` and `--fail-on-regression` behave as specified.
