# Engine Benchmark Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a headless, zero-dependency benchmark suite (`bench/`) that measures the D3D engine's Ruby-side speed and reports per-case deltas against a committed baseline, so an AI optimization loop can detect real improvements vs. noise.

**Architecture:** A small custom timing harness (warmup + auto-calibration + median-of-rounds + noise band) drives benchmark cases grouped by engine area. Pure logic (delta %, verdict classification, baseline JSON I/O) lives in focused, unit-tested files. The CLI runner loads the full engine via `$LOAD_PATH`, runs cases, and prints a table or JSON comparing the current run to `bench/baseline.json`.

**Tech Stack:** Pure Ruby (system CRuby/MRI), stdlib `json` only, `minitest` for tests (same as existing `tests/`). No gems, no DragonRuby runtime.

---

## Spec Reference

Implements `docs/superpowers/specs/2026-06-15-engine-benchmark-harness-design.md`.

## File Structure

```
bench/
  report.rb           # Bench::Report — delta_percent, verdict, format_table (pure)
  baseline.rb         # Bench::Baseline — load/save JSON baseline (pure)
  harness.rb          # Bench::Registry (case registration) + Bench::Timer (measurement)
  scenes.rb           # Scenes — deterministic fixtures (cameras, models, voxel world)
  cases/
    math_bench.rb     # math/* cases
    render_bench.rb   # render/* cases
    voxel_bench.rb    # voxel/* cases
    physics_bench.rb  # physics/* cases
  bench.rb            # CLI runner: load engine, run cases, compare, report
  baseline.json       # committed baseline (generated in final task)
  README.md           # usage + CRuby/mruby caveat
tests/
  bench_report_test.rb
  bench_baseline_test.rb
  bench_harness_test.rb
  bench_scenes_test.rb
```

**Key naming contract (used across tasks — keep consistent):**
- `Bench::Case = Struct.new(:name, :setup, :body)` → `.name`, `.setup`, `.body`
- `Bench::Registry.register(name, setup: nil, &body)`, `Bench::Registry.cases`, `Bench::Registry.reset!`
- `Bench::Timer.measure(setup:, body:, target_time: 0.3, rounds: 5, warmup: 20)` → `{ ns_per_op:, noise: }`
- `Bench::Report.delta_percent(baseline_ns, current_ns)` → Float or nil
- `Bench::Report.verdict(delta_pct, noise_pct, floor_pct = 2.0)` → `:faster | :slower | :within_noise | :new`
- `Bench::Report.format_table(rows)` → String
- `Bench::Baseline.load(path)` → Hash (name → {"ns_per_op", "noise"}) or nil; `Bench::Baseline.save(path, results)` where `results = [{ name:, ns_per_op:, noise: }]`
- `Scenes.camera_overview`, `Scenes.cube_grid(n, textured:)`, `Scenes.sphere_field(count)`, `Scenes.voxel_world`
- Engine entry points (already exist): `D3D::Renderer.render(camera, models)`, `D3D::Renderer.render_voxel_world(camera, world)`, `D3D::Collisions.ray_model(o, d, model)`, `D3D::Collisions.sphere_model(center, radius, model)`, `D3D::VoxelBody#move(world, dt)`, `D3D::VoxelWorld#raycast(origin, dir, max)`, `#aabb_intersects?(min, max)`, `#rebuild!`

---

## Task 1: Report logic (delta % + verdict)

**Files:**
- Create: `bench/report.rb`
- Test: `tests/bench_report_test.rb`

- [ ] **Step 1: Write the failing test**

Create `tests/bench_report_test.rb`:

```ruby
require "minitest/autorun"
require_relative "../bench/report"

class BenchReportTest < Minitest::Test
  def test_delta_percent_basic
    assert_in_delta(-20.0, Bench::Report.delta_percent(100.0, 80.0), 1e-9)
    assert_in_delta(25.0, Bench::Report.delta_percent(100.0, 125.0), 1e-9)
  end

  def test_delta_percent_nil_or_zero_baseline
    assert_nil Bench::Report.delta_percent(nil, 80.0)
    assert_nil Bench::Report.delta_percent(0.0, 80.0)
  end

  def test_verdict_within_noise_uses_floor
    # 1% change, no measured noise -> 2% floor dominates -> within noise
    assert_equal :within_noise, Bench::Report.verdict(1.0, 0.0)
  end

  def test_verdict_within_noise_uses_measured_noise
    # 3% change but measured noise band 5% -> within noise
    assert_equal :within_noise, Bench::Report.verdict(3.0, 5.0)
  end

  def test_verdict_faster_and_slower
    assert_equal :faster, Bench::Report.verdict(-8.0, 2.0)
    assert_equal :slower, Bench::Report.verdict(8.0, 2.0)
  end

  def test_verdict_new_when_delta_nil
    assert_equal :new, Bench::Report.verdict(nil, 0.0)
  end

  def test_format_table_includes_names_and_summary
    rows = [
      { name: "a/one", baseline_ns: 100.0, current_ns: 80.0, delta_pct: -20.0, noise: 1.0, verdict: :faster },
      { name: "b/two", baseline_ns: nil, current_ns: 5.0, delta_pct: nil, noise: 0.0, verdict: :new }
    ]
    out = Bench::Report.format_table(rows)
    assert_includes out, "a/one"
    assert_includes out, "b/two"
    assert_includes out, "summary:"
    assert_includes out, "1 faster"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby tests/bench_report_test.rb`
Expected: FAIL — `cannot load such file -- .../bench/report` (file does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `bench/report.rb`:

```ruby
module Bench
  module Report
    FLOOR_PCT = 2.0

    module_function

    # Percent change from baseline to current. Negative = faster (less time).
    # Returns nil when there is no usable baseline.
    def delta_percent(baseline_ns, current_ns)
      return nil if baseline_ns.nil? || baseline_ns.zero?
      (current_ns - baseline_ns) / baseline_ns * 100.0
    end

    # Classify a delta against the noise band and a minimum floor.
    def verdict(delta_pct, noise_pct, floor_pct = FLOOR_PCT)
      return :new if delta_pct.nil?
      threshold = [noise_pct || 0.0, floor_pct].max
      return :within_noise if delta_pct.abs <= threshold
      delta_pct < 0 ? :faster : :slower
    end

    # rows: [{ name:, baseline_ns:, current_ns:, delta_pct:, noise:, verdict: }]
    def format_table(rows)
      fmt = "%-34s %14s %14s %9s  %s"
      header = format(fmt, "case", "baseline ns/op", "current ns/op", "delta%", "verdict")
      lines = [header, "-" * header.length]

      counts = { faster: 0, slower: 0, within_noise: 0, new: 0 }
      rows.each do |row|
        counts[row[:verdict]] += 1 if counts.key?(row[:verdict])
        base = row[:baseline_ns] ? format("%.1f", row[:baseline_ns]) : "-"
        cur = format("%.1f", row[:current_ns])
        delta = row[:delta_pct] ? format("%+.1f%%", row[:delta_pct]) : "-"
        lines << format(fmt, row[:name], base, cur, delta, row[:verdict].to_s)
      end

      lines << ""
      lines << "summary: #{counts[:faster]} faster, #{counts[:slower]} slower, " \
               "#{counts[:within_noise]} within-noise, #{counts[:new]} new"
      lines.join("\n")
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `ruby tests/bench_report_test.rb`
Expected: PASS (all assertions, 0 failures, 0 errors).

- [ ] **Step 5: Commit**

```bash
git add bench/report.rb tests/bench_report_test.rb
git commit -m "add bench report delta/verdict logic"
```

---

## Task 2: Baseline JSON load/save

**Files:**
- Create: `bench/baseline.rb`
- Test: `tests/bench_baseline_test.rb`

- [ ] **Step 1: Write the failing test**

Create `tests/bench_baseline_test.rb`:

```ruby
require "minitest/autorun"
require "tmpdir"
require_relative "../bench/baseline"

class BenchBaselineTest < Minitest::Test
  def test_load_missing_returns_nil
    missing = File.join(Dir.tmpdir, "d3d_bench_does_not_exist.json")
    assert_nil Bench::Baseline.load(missing)
  end

  def test_save_then_load_roundtrip
    Dir.mktmpdir do |dir|
      path = File.join(dir, "baseline.json")
      results = [
        { name: "a/x", ns_per_op: 123.4, noise: 2.5 },
        { name: "b/y", ns_per_op: 9.0, noise: 0.0 }
      ]
      Bench::Baseline.save(path, results)
      loaded = Bench::Baseline.load(path)

      assert_in_delta 123.4, loaded["a/x"]["ns_per_op"], 1e-9
      assert_in_delta 2.5,   loaded["a/x"]["noise"], 1e-9
      assert_in_delta 9.0,   loaded["b/y"]["ns_per_op"], 1e-9
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby tests/bench_baseline_test.rb`
Expected: FAIL — `cannot load such file -- .../bench/baseline`.

- [ ] **Step 3: Write minimal implementation**

Create `bench/baseline.rb`:

```ruby
require "json"

module Bench
  module Baseline
    module_function

    # Returns a Hash mapping case name => { "ns_per_op" => Float, "noise" => Float },
    # or nil when the baseline file does not exist.
    def load(path)
      return nil unless File.exist?(path)
      data = JSON.parse(File.read(path))
      data["cases"]
    end

    # results: [{ name:, ns_per_op:, noise: }]
    def save(path, results)
      cases = {}
      results.each do |r|
        cases[r[:name]] = { "ns_per_op" => r[:ns_per_op], "noise" => r[:noise] }
      end
      File.write(path, JSON.pretty_generate({ "cases" => cases }) + "\n")
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `ruby tests/bench_baseline_test.rb`
Expected: PASS (0 failures, 0 errors).

- [ ] **Step 5: Commit**

```bash
git add bench/baseline.rb tests/bench_baseline_test.rb
git commit -m "add bench baseline json load/save"
```

---

## Task 3: Timing harness (registry + timer)

**Files:**
- Create: `bench/harness.rb`
- Test: `tests/bench_harness_test.rb`

- [ ] **Step 1: Write the failing test**

Create `tests/bench_harness_test.rb`:

```ruby
require "minitest/autorun"
require_relative "../bench/harness"

class BenchHarnessTest < Minitest::Test
  def setup
    Bench::Registry.reset!
  end

  def test_register_and_list_preserves_order
    Bench::Registry.register("t/one") { |_| 1 + 1 }
    Bench::Registry.register("t/two", setup: -> { 41 }) { |fx| fx + 1 }
    assert_equal ["t/one", "t/two"], Bench::Registry.cases.map(&:name)
  end

  def test_case_exposes_setup_and_body
    c = Bench::Registry.register("t/three", setup: -> { 10 }) { |fx| fx * 2 }
    assert_equal 10, c.setup.call
    assert_equal 20, c.body.call(c.setup.call)
  end

  def test_measure_returns_finite_positive_stats
    stats = Bench::Timer.measure(
      setup: -> { [1, 2, 3] },
      body: ->(fx) { fx.reduce(:+) },
      target_time: 0.01,
      rounds: 3,
      warmup: 2
    )
    assert stats[:ns_per_op] > 0
    assert stats[:ns_per_op].finite?
    assert stats[:noise] >= 0
  end

  def test_measure_works_without_setup
    stats = Bench::Timer.measure(
      setup: nil,
      body: ->(_fx) { 2 * 2 },
      target_time: 0.01,
      rounds: 2,
      warmup: 1
    )
    assert stats[:ns_per_op] > 0
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby tests/bench_harness_test.rb`
Expected: FAIL — `cannot load such file -- .../bench/harness`.

- [ ] **Step 3: Write minimal implementation**

Create `bench/harness.rb`:

```ruby
module Bench
  Case = Struct.new(:name, :setup, :body)

  module Registry
    @cases = []

    class << self
      def register(name, setup: nil, &body)
        c = Case.new(name, setup, body)
        @cases << c
        c
      end

      def cases
        @cases
      end

      def reset!
        @cases = []
      end
    end
  end

  module Timer
    module_function

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Returns { ns_per_op: Float, noise: Float } where noise is the relative
    # spread across rounds (percent of the median).
    def measure(setup:, body:, target_time: 0.3, rounds: 5, warmup: 20)
      fixture = setup ? setup.call : nil

      warmup.times { body.call(fixture) }

      iters = calibrate(body, fixture, target_time)

      seconds_per_op = []
      rounds.times do
        GC.start
        t0 = clock
        iters.times { body.call(fixture) }
        elapsed = clock - t0
        seconds_per_op << elapsed / iters
      end

      seconds_per_op.sort!
      median = seconds_per_op[seconds_per_op.length / 2]
      lo = seconds_per_op.first
      hi = seconds_per_op.last
      noise = median > 0 ? (hi - lo) / median * 100.0 : 0.0

      { ns_per_op: median * 1e9, noise: noise }
    end

    # Scale iteration count so one measured batch runs ~target_time seconds.
    def calibrate(body, fixture, target_time)
      iters = 1
      loop do
        t0 = clock
        iters.times { body.call(fixture) }
        elapsed = clock - t0

        return iters if iters >= 100_000_000
        return iters if elapsed >= target_time

        if elapsed <= 0.0
          iters *= 100
        else
          factor = (target_time / elapsed * 1.2).ceil
          factor = 2 if factor < 2
          factor = 1000 if factor > 1000
          iters *= factor
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `ruby tests/bench_harness_test.rb`
Expected: PASS (0 failures, 0 errors).

- [ ] **Step 5: Commit**

```bash
git add bench/harness.rb tests/bench_harness_test.rb
git commit -m "add bench timing harness (registry + timer)"
```

---

## Task 4: Deterministic scenes (fixtures)

**Files:**
- Create: `bench/scenes.rb`
- Test: `tests/bench_scenes_test.rb`

Note: `scenes.rb` references `D3D::*` and assumes the engine is already loaded by the caller (the runner and the test both load it first). It does not require the engine itself.

- [ ] **Step 1: Write the failing test**

Create `tests/bench_scenes_test.rb`:

```ruby
require "minitest/autorun"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(ROOT) unless $LOAD_PATH.include?(ROOT)
require "app/d3d/d3d.rb"
require_relative "../bench/scenes"

class BenchScenesTest < Minitest::Test
  def test_cube_grid_count
    models = Scenes.cube_grid(4, textured: false)
    assert_equal 16, models.length
    assert(models.all? { |m| m.is_a?(D3D::Model) })
  end

  def test_cube_grid_solid_has_no_texture
    models = Scenes.cube_grid(2, textured: false)
    assert(models.all? { |m| m.texture.nil? })
  end

  def test_cube_grid_textured_sets_texture
    models = Scenes.cube_grid(2, textured: true)
    assert(models.all? { |m| !m.texture.nil? })
  end

  def test_sphere_field_count
    assert_equal 10, Scenes.sphere_field(10).length
  end

  def test_voxel_world_has_blocks
    world = Scenes.voxel_world
    assert world.block_count > 0
  end

  def test_camera_overview_returns_camera
    assert_instance_of D3D::Camera, Scenes.camera_overview
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby tests/bench_scenes_test.rb`
Expected: FAIL — `cannot load such file -- .../bench/scenes`.

- [ ] **Step 3: Write minimal implementation**

Create `bench/scenes.rb`:

```ruby
# Deterministic benchmark fixtures. Assumes the D3D engine is already loaded.
module Scenes
  module_function

  def camera_overview
    cam = D3D::Camera.new(position: D3D::Vec3.new(12.0, 10.0, 18.0))
    cam.look_at(D3D::Vec3.new(0.0, 0.0, 0.0))
    cam
  end

  # n x n grid of cubes centered on the origin. Shares one mesh across models.
  def cube_grid(n, textured: false)
    mesh = D3D::Mesh.cube
    models = []
    n.times do |i|
      n.times do |j|
        x = (i - n / 2) * 2.0
        z = (j - n / 2) * 2.0
        models << D3D::Model.new(
          mesh: mesh,
          texture: textured ? "sprites/block.png" : nil,
          position: D3D::Vec3.new(x, 0.0, z),
          color: { r: 200, g: 100, b: 50, a: 255 }
        )
      end
    end
    models
  end

  # `count` spheres arranged in a deterministic spiral.
  def sphere_field(count)
    mesh = D3D::Mesh.sphere(radius: 0.8, segments: 16, rings: 16)
    models = []
    count.times do |i|
      angle = i * 0.618 * Math::PI * 2
      r = 2.0 + i * 0.4
      models << D3D::Model.new(
        mesh: mesh,
        position: D3D::Vec3.new(Math.cos(angle) * r, 0.0, Math.sin(angle) * r),
        color: { r: 80, g: 160, b: 220, a: 255 }
      )
    end
    models
  end

  # 16x16 columns of blocks with a deterministic height field. Mesh prebuilt.
  def voxel_world
    world = D3D::VoxelWorld.new
    size = 16
    size.times do |x|
      size.times do |z|
        height = 1 + ((Math.sin(x * 0.4) + Math.cos(z * 0.4)) * 2.0).to_i.abs
        (0..height).each do |y|
          world.add_block(x, y, z, { r: 120, g: 180, b: 90, a: 255 })
        end
      end
    end
    world.rebuild!
    world
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `ruby tests/bench_scenes_test.rb`
Expected: PASS (0 failures, 0 errors). This also confirms the full engine loads under system Ruby via `$LOAD_PATH`.

- [ ] **Step 5: Commit**

```bash
git add bench/scenes.rb tests/bench_scenes_test.rb
git commit -m "add deterministic benchmark scenes"
```

---

## Task 5: Benchmark cases (math, render, voxel, physics)

**Files:**
- Create: `bench/cases/math_bench.rb`
- Create: `bench/cases/render_bench.rb`
- Create: `bench/cases/voxel_bench.rb`
- Create: `bench/cases/physics_bench.rb`

These files register cases via `Bench::Registry.register`. They are exercised end-to-end by the runner smoke test in Task 6 (no separate unit test — a per-case unit test would just re-run the engine the runner already covers).

- [ ] **Step 1: Create the math cases**

Create `bench/cases/math_bench.rb`:

```ruby
Bench::Registry.register(
  "math/mat4_multiply",
  setup: lambda do
    a = D3D::Mat4.translation(1.0, 2.0, 3.0) * D3D::Mat4.rotation(0.3, 0.5, 0.7)
    b = D3D::Mat4.scale(1.5, 2.0, 0.5) * D3D::Mat4.rotation(0.1, 0.2, 0.3)
    [a, b]
  end
) { |fx| fx[0] * fx[1] }

Bench::Registry.register(
  "math/vec3_ops",
  setup: -> { [D3D::Vec3.new(1.0, 2.0, 3.0), D3D::Vec3.new(-0.5, 4.0, 2.5)] }
) do |fx|
  a, b = fx
  c = a + b
  d = a - b
  c.dot(d)
  a.cross(b).normalize
  a.length
end

Bench::Registry.register(
  "math/camera_view_matrix",
  setup: lambda do
    cam = D3D::Camera.new(position: D3D::Vec3.new(5.0, 4.0, 8.0))
    cam.look_at(D3D::Vec3.new(0.0, 0.0, 0.0))
    cam
  end
) do |cam|
  cam.invalidate_view!
  cam.get_view_matrix
end
```

- [ ] **Step 2: Create the render cases**

Create `bench/cases/render_bench.rb`:

```ruby
Bench::Registry.register(
  "render/cubes_grid_solid",
  setup: -> { [Scenes.camera_overview, Scenes.cube_grid(8, textured: false)] }
) { |fx| D3D::Renderer.render(fx[0], fx[1]) }

Bench::Registry.register(
  "render/cubes_grid_textured",
  setup: -> { [Scenes.camera_overview, Scenes.cube_grid(8, textured: true)] }
) { |fx| D3D::Renderer.render(fx[0], fx[1]) }

Bench::Registry.register(
  "render/spheres",
  setup: -> { [Scenes.camera_overview, Scenes.sphere_field(16)] }
) { |fx| D3D::Renderer.render(fx[0], fx[1]) }

Bench::Registry.register(
  "render/voxel_world",
  setup: -> { [Scenes.camera_overview, Scenes.voxel_world] }
) { |fx| D3D::Renderer.render_voxel_world(fx[0], fx[1]) }
```

- [ ] **Step 3: Create the voxel cases**

Create `bench/cases/voxel_bench.rb`:

```ruby
Bench::Registry.register(
  "voxel/build_mesh",
  setup: -> { Scenes.voxel_world }
) { |world| world.rebuild! }

Bench::Registry.register(
  "voxel/raycast",
  setup: lambda do
    world = Scenes.voxel_world
    origin = D3D::Vec3.new(0.5, 20.0, 0.5)
    dir = D3D::Vec3.new(0.3, -1.0, 0.2).normalize
    [world, origin, dir]
  end
) { |fx| fx[0].raycast(fx[1], fx[2], 64.0) }

Bench::Registry.register(
  "voxel/aabb_query",
  setup: lambda do
    world = Scenes.voxel_world
    min = D3D::Vec3.new(0.0, 0.0, 0.0)
    max = D3D::Vec3.new(1.0, 2.0, 1.0)
    [world, min, max]
  end
) { |fx| fx[0].aabb_intersects?(fx[1], fx[2]) }
```

- [ ] **Step 4: Create the physics cases**

Create `bench/cases/physics_bench.rb`:

```ruby
Bench::Registry.register(
  "physics/ray_model",
  setup: lambda do
    model = D3D::Model.new(mesh: D3D::Mesh.sphere(radius: 1.0, segments: 16, rings: 16))
    [D3D::Vec3.new(0.0, 0.0, 5.0), D3D::Vec3.new(0.0, 0.0, -1.0), model]
  end
) { |fx| D3D::Collisions.ray_model(fx[0], fx[1], fx[2]) }

Bench::Registry.register(
  "physics/sphere_model",
  setup: lambda do
    model = D3D::Model.new(mesh: D3D::Mesh.sphere(radius: 1.0, segments: 16, rings: 16))
    [D3D::Vec3.new(0.0, 0.0, 0.0), model]
  end
) { |fx| D3D::Collisions.sphere_model(fx[0], 1.2, fx[1]) }

Bench::Registry.register(
  "physics/voxel_body_move",
  setup: lambda do
    [Scenes.voxel_world, D3D::VoxelBody.new(0.5, 20.0, 0.5)]
  end
) do |fx|
  world, body = fx
  # Reset state each iteration so every measured op does the same work.
  body.position.x = 0.5
  body.position.y = 20.0
  body.position.z = 0.5
  body.velocity.x = 2.0
  body.velocity.y = 0.0
  body.velocity.z = 1.0
  body.move(world, 1.0 / 60.0)
end
```

- [ ] **Step 5: Commit**

```bash
git add bench/cases/
git commit -m "add benchmark cases for math, render, voxel, physics"
```

---

## Task 6: CLI runner

**Files:**
- Create: `bench/bench.rb`

The runner is verified by a real run (smoke test) rather than minitest, since it is an integration entry point that loads the engine and times real cases.

- [ ] **Step 1: Write the runner**

Create `bench/bench.rb`:

```ruby
#!/usr/bin/env ruby
require "json"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(ROOT) unless $LOAD_PATH.include?(ROOT)
require "app/d3d/d3d.rb"

require_relative "harness"
require_relative "report"
require_relative "baseline"
require_relative "scenes"
Dir[File.join(__dir__, "cases", "*.rb")].sort.each { |f| require f }

BASELINE_PATH = File.join(__dir__, "baseline.json")

save = ARGV.include?("--save")
as_json = ARGV.include?("--json")
fail_on_regression = ARGV.include?("--fail-on-regression")
filter = (idx = ARGV.index("--filter")) ? ARGV[idx + 1] : nil

cases = Bench::Registry.cases
cases = cases.select { |c| c.name.include?(filter) } if filter

if cases.empty?
  warn "No benchmark cases matched#{filter ? " filter #{filter.inspect}" : ''}."
  exit 1
end

results = cases.map do |c|
  stats = Bench::Timer.measure(setup: c.setup, body: c.body)
  { name: c.name, ns_per_op: stats[:ns_per_op], noise: stats[:noise] }
end

Bench::Baseline.save(BASELINE_PATH, results) if save

baseline = Bench::Baseline.load(BASELINE_PATH)
rows = results.map do |r|
  base = baseline && baseline[r[:name]]
  base_ns = base && base["ns_per_op"]
  delta = Bench::Report.delta_percent(base_ns, r[:ns_per_op])
  {
    name: r[:name],
    baseline_ns: base_ns,
    current_ns: r[:ns_per_op],
    delta_pct: delta,
    noise: r[:noise],
    verdict: Bench::Report.verdict(delta, r[:noise])
  }
end

if as_json
  puts JSON.pretty_generate(rows)
else
  puts Bench::Report.format_table(rows)
end

exit 2 if fail_on_regression && rows.any? { |row| row[:verdict] == :slower }
```

- [ ] **Step 2: Smoke-run a single fast case**

Run: `ruby bench/bench.rb --filter math/vec3_ops`
Expected: prints a table with a row `math/vec3_ops`, a positive `current ns/op`, verdict `new` (no baseline yet), and a `summary:` line. Exit code 0.

- [ ] **Step 3: Smoke-run the full suite as JSON**

Run: `ruby bench/bench.rb --json`
Expected: a JSON array with one object per registered case (13 total: 3 math, 4 render, 3 voxel, 3 physics). Each object has `name`, `current_ns`, `verdict`. No exceptions raised (confirms every case's setup/body runs under system Ruby).

Note: if any case raises, fix that case file (Task 5) before continuing.

- [ ] **Step 4: Commit**

```bash
git add bench/bench.rb
git commit -m "add benchmark CLI runner"
```

---

## Task 7: Generate baseline, document, and verify the loop

**Files:**
- Create: `bench/baseline.json` (generated)
- Create: `bench/README.md`

- [ ] **Step 1: Generate and commit the baseline**

Run: `ruby bench/bench.rb --save`
Expected: prints the table (all verdicts `within-noise`, since it compares the just-saved baseline to itself), and writes `bench/baseline.json`.

- [ ] **Step 2: Verify stability (no-change run reports within-noise)**

Run: `ruby bench/bench.rb`
Expected: every case verdict is `within-noise` (or at worst a stray `faster`/`slower` on one case — if more than one case shows a non-noise verdict on an unchanged codebase, the noise floor/round count needs raising; bump `rounds:` to 7 or `FLOOR_PCT` to 3.0 and regenerate the baseline).

- [ ] **Step 3: Verify regression detection**

Run: `ruby bench/bench.rb --filter math/vec3_ops --fail-on-regression; echo "exit=$?"`
Expected: exit 0 (unchanged). This confirms the gate runs. (A deliberate slowdown is not committed; this only checks the flag path executes.)

- [ ] **Step 4: Write the README**

Create `bench/README.md`:

```markdown
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
```

Each case reports median `ns/op` across rounds plus a noise band. A change counts
as `faster`/`slower` only when it exceeds `max(noise band, 2%)`; otherwise it is
`within-noise`.

## Optimization loop

1. `ruby bench/bench.rb --save` once to lock a baseline.
2. Make an optimization.
3. `ruby bench/bench.rb` to see per-case deltas and verdicts.
4. Keep changes that show `faster` beyond noise; revert ones that show `slower`.
5. `ruby bench/bench.rb --save` to lock the improved baseline.

## Coverage

- `math/*` — Mat4 multiply, Vec3 ops, camera view matrix
- `render/*` — solid + textured cube grids, sphere field, voxel world rendering
- `voxel/*` — mesh rebuild, DDA raycast, AABB query
- `physics/*` — ray-model, sphere-model, voxel body movement

## Caveat: CRuby vs mruby

These benchmarks run on CRuby/MRI, but the game runs on DragonRuby's mruby.
Algorithmic improvements and allocation reductions transfer reliably across both;
CRuby-specific micro-optimizations may not. Use these numbers to guide the
optimization loop, and spot-check big wins in-game before trusting them. An
in-game frame-time benchmark can be added later as ground truth.
```

- [ ] **Step 5: Run the full test suite to confirm nothing broke**

Run: `for f in tests/*.rb; do ruby "$f"; done`
Expected: all test files pass (existing voxel/face tests plus the four new bench tests), 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add bench/baseline.json bench/README.md
git commit -m "add benchmark baseline and docs"
```

---

## Final Verification Checklist

- [ ] `ruby bench/bench.rb` runs all cases and prints a table with deltas vs. baseline.
- [ ] `ruby bench/bench.rb --save` writes `bench/baseline.json`.
- [ ] A second unchanged run reports cases as `within-noise`.
- [ ] `--json` emits one object per case; `--filter` subsets; `--fail-on-regression` exits non-zero only on a `slower` verdict.
- [ ] `for f in tests/*.rb; do ruby "$f"; done` passes, including the four new bench tests.
```
